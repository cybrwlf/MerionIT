#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Wipe a used laptop down to "waiting for a new user": back up and remove every named user, reset the
    name, bring it up to the current Merion / Mainline standards, and log what was done.

.DESCRIPTION
    Written 2026-11-04 with Ricardo after offboarding MRM8075-LT101 (PNoon) and MRQ7582-LT301 (mlaw).

    1. USERS. Every local account and profile not on the protected list (pcsadmin, TempUser, operator,
       administrator, scan, default, public, and Windows' own built-in accounts) is backed up and removed
       with the newest manual\backup-userfiles-*.ps1 (-IncludeDownloads -AllowCloudOnly): local files only,
       Downloads filtered, nothing removed unless the backup verified. Machines are company owned and
       usually set up for one person, but there can be more, so all of them are listed, none is singled out.
    2. NAME. MRQ / MRP / MIP: the 4 digits are the user's phone extension, so they become 7500
       ("waiting for a new user"): MRQ7582-LT301 -> MRQ7500-LT301. MRM (property code) and MITLOAN keep
       their name. Anything else is refused before a single change is made.
    3. STANDARDS. C:\MerionIT is refreshed first (setup deletes RenamePC/DefaultAccounts after a build, so
       an old copy cannot re-run setup), then:
         USB    : the full setup, setup\Step1-Accounts-Apps.ps1 -Unattended (Step 2 included), no named user.
         Remote : only the parts that apply to the whole machine, because nobody is signed in (Kaseya runs
                  this as SYSTEM): accounts, BGInfo, apps, Office, bloat / McAfee removal, Windows Update
                  cache, vendor drivers, power plan, Windows Update policy, Set-MerionStandards and the
                  Default profile (whoever signs in first gets the per-user settings and taskbar pins from
                  it, as with Add-User.bat). Per-user Start menu / taskbar tweaks are not run.
    4. REBOOT, then a startup task (SYSTEM) runs Agent-Install.ps1 so the Kaseya agent is reinstalled under
       the new name (/r /w), runs tools\Test-MerionBuild.ps1, adds both results to the log and removes itself.
       A machine with NO agent is left without one (Ricardo, 2026-11-04): Setup.bat for the new user installs
       it. Step 1 gets -SkipAgent and nothing here installs it, so the build check's kaseya FAIL is expected.

    WHERE THE BACKUP GOES
      USB    : <USB>\MerionIT-Offboard\<old name>_<timestamp>\, log beside it, one line in
               <USB>\MerionIT-Offboard\index.csv.
      Remote : staged in C:\MerionIT\offboard\, then packed into <old name>_<timestamp>.7z (AES-256 with
               encrypted file names, password = pcsadmin's from secrets.psd1). The plain copy is deleted only
               after the archive tests OK and holds the same number of files. At HQ, run this with -Collect
               and the USB plugged in: it tests and extracts each archive to the USB, compares file counts,
               writes index.csv, and only then deletes the archive from the laptop.
      7-Zip cannot take the password on stdin (tested 2026-11-04, 7-Zip 26.02: it rejects the right
      password), so it is passed on 7-Zip's command line. It is never printed or logged; it is visible in
      the process list, to administrators of that laptop, while the archive is built.

    SECRETS
      Needs C:\MerionIT\secrets.psd1 (pcsadmin's password for the archive and for the accounts step).
      USB: copied in from the USB with the repo. Remote: a Kaseya procedure writes it first. This script
      deletes C:\MerionIT\secrets.psd1 at the end whatever happens, and never touches the USB's copy.

.PARAMETER UsbRoot
    USB mode: the drive or folder the backup goes to. Defaults to the drive this script runs from.
.PARAMETER Remote
    Use the remote behaviour (archive on C:, machine-wide setup only). Automatic when running as SYSTEM.
.PARAMETER Collect
    At HQ: move the archives in C:\MerionIT\offboard to <UsbRoot>\MerionIT-Offboard.
.PARAMETER SkipRefresh
    Use C:\MerionIT as it is: no copy from USB, no GitHub pull. For testing scripts not yet pushed.
.PARAMETER Force
    No confirmation prompt. Implied by -Remote.

.EXAMPLE
    E:\MerionIT\manual\Reset-ForNewUser.ps1 -WhatIf          # from USB: show users, new name, what is copied
    E:\MerionIT\manual\Reset-ForNewUser.ps1                  # from USB: do it (asks once)
    powershell.exe -ExecutionPolicy Bypass -File C:\MerionIT\manual\Reset-ForNewUser.ps1 -Remote   # Kaseya
    E:\MerionIT\manual\Reset-ForNewUser.ps1 -Collect         # at HQ, after a remote run

.NOTES
    Write-Output only (Kaseya runs this as SYSTEM). TLS 1.2 and -UseBasicParsing for the GitHub pull.
    Remote mode has not run end to end yet (2026-11-04): winget as SYSTEM and the Default-profile seeding
    as SYSTEM are the parts most likely to need a fix.
    Exit code: 0 = done, 2 = stopped or something needs a look (see the log).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$UsbRoot,
    [switch]$Remote,
    [switch]$Collect,
    [switch]$SkipRefresh,
    [switch]$Force,
    # Internal: run by the startup task after the reboot.
    [switch]$AfterReboot
)

$ScriptVersion = '2026-11-04.1'
$dryRun = [bool]$WhatIfPreference
$WhatIfPreference = $false

$MerionITRoot = 'C:\MerionIT'
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$statePath = "$MerionITRoot\.reset-state.json"
$taskName = 'MerionIT Reset - after reboot'
$secretsPath = "$MerionITRoot\secrets.psd1"
$offboardLocal = "$MerionITRoot\offboard"
$installedCopy = "$MerionITRoot\manual\Reset-ForNewUser.ps1"
# Same list as manual\backup-userfiles-*.ps1. Built-in accounts (Administrator, Guest, DefaultAccount,
# WDAGUtilityAccount) are excluded by RID, whatever they are called.
$Protected = 'operator*', 'administrator*', 'TempUser*', 'PCSadmin*', 'public*', 'scan*', 'default*', 'All Users'
$builtinRid = '-(500|501|503|504)$'

$script:logFiles = @()
function Say($m) {
    Write-Output $m
    foreach ($f in $script:logFiles) { Add-Content -LiteralPath $f -Value $m -ErrorAction SilentlyContinue }
}
function Test-Protected([string]$Name) { [bool]($Protected | Where-Object { $Name -like $_ }) }

function Get-SevenZip {
    @("$env:ProgramData\scoop\apps\7zip\current\7z.exe", "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
function Get-PcsAdminPassword([string[]]$Paths) {
    foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p) {
            $pw = (Import-PowerShellDataFile -LiteralPath $p).PcsAdminPassword
            if ($pw) { return $pw }
        }
    }
}
# Number of files (not folders) in an archive. Returns -1 when it cannot be read (wrong password etc).
function Get-ArchiveFileCount([string]$SevenZip, [string]$Archive, [string]$Password) {
    $list = & $SevenZip l -slt "-p$Password" $Archive 2>$null
    if ($LASTEXITCODE -ne 0) { return -1 }
    @($list | Where-Object { $_ -match '^Attributes = ' -and $_ -notmatch '^Attributes = \S*D' }).Count
}
function Get-FileCount([string]$Path) { @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue).Count }
function Add-IndexLine([string]$Root, $Row) {
    $index = Join-Path $Root 'index.csv'
    $Row | Export-Csv -LiteralPath $index -Append -NoTypeInformation -Encoding UTF8
}

# ================================================================== -AfterReboot (startup task, SYSTEM)
if ($AfterReboot) {
    $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($state) { $script:logFiles = @($state.LogFiles | Where-Object { Test-Path -LiteralPath (Split-Path $_ -Parent) }) }
    Say ''
    Say "== After reboot, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), running as $env:COMPUTERNAME"
    # The agent download and its health check need the network, which can lag a cold boot.
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-NetConnection 'managedsupport.kaseya.net' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue) { break }
        Start-Sleep -Seconds 10
    }
    if (Test-Path "$MerionITRoot\.agent-repair-pending") {
        Say 'Kaseya agent repair (/r /w) for the new name:'
        & "$MerionITRoot\setup\Agent-Install.ps1" *>&1 | ForEach-Object { Say "  $_" }
    }
    Say 'Build check:'
    & "$MerionITRoot\tools\Test-MerionBuild.ps1" | ForEach-Object { Say "  $_" }
    if (-not (Get-Service | Where-Object { $_.DisplayName -like '*Kaseya Agent*' })) {
        Say '  (kaseya FAIL is expected here: the agent was not on this machine and is not reinstalled until Setup.bat for the new user.)'
    }
    if (Test-Path -LiteralPath $secretsPath) { Remove-Item -LiteralPath $secretsPath -Force; Say 'Deleted a leftover secrets.psd1.' }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    Say $(if (Get-Service | Where-Object { $_.DisplayName -like '*Kaseya Agent*' }) { 'Reset finished. Check the machine in the Kaseya portal and move it to its proper group.' } else { 'Reset finished. No Kaseya agent on purpose: Setup.bat for the new user installs it.' })
    exit 0
}

# ================================================================== -Collect (at HQ)
if ($Collect) {
    if (-not $UsbRoot) { $UsbRoot = Split-Path -Qualifier $PSScriptRoot }
    $dest = Join-Path $UsbRoot.TrimEnd('\') 'MerionIT-Offboard'
    $sevenZip = Get-SevenZip
    if (-not $sevenZip) { Write-Output 'ERROR: 7-Zip not found on this machine.'; exit 2 }
    $pw = Get-PcsAdminPassword @((Join-Path (Split-Path $PSScriptRoot -Parent) 'secrets.psd1'), $secretsPath)
    if (-not $pw) { Write-Output 'ERROR: no secrets.psd1 with PcsAdminPassword on the USB repo folder or in C:\MerionIT.'; exit 2 }
    $archives = @(Get-ChildItem -LiteralPath $offboardLocal -Filter '*.7z' -ErrorAction SilentlyContinue)
    if (-not $archives) { Write-Output "Nothing to collect in $offboardLocal."; exit 0 }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $bad = 0
    foreach ($a in $archives) {
        $name = $a.BaseName
        $target = Join-Path $dest $name
        Write-Output "== $($a.Name) -> $target"
        & $sevenZip t "-p$pw" $a.FullName -bso0 -bsp0 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Output "   FAILED: archive test (exit $LASTEXITCODE). Left on the laptop."; $bad++; continue }
        $inArchive = Get-ArchiveFileCount $sevenZip $a.FullName $pw
        if ($dryRun) { Write-Output "   What if: extract $inArchive file(s) here, then delete the archive from the laptop."; continue }
        & $sevenZip x "-p$pw" $a.FullName "-o$target" -aoa -bso0 -bsp0 2>$null
        $extracted = Get-FileCount $target
        if ($LASTEXITCODE -ne 0 -or $extracted -ne $inArchive) {
            Write-Output "   FAILED: 7-Zip exit $LASTEXITCODE, $extracted of $inArchive file(s) on the USB. Archive left on the laptop."
            $bad++; continue
        }
        $log = [IO.Path]::ChangeExtension($a.FullName, '.log')
        if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log -Destination (Join-Path $target 'Reset-ForNewUser.log') -Force }
        $row = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($a.FullName, '.json')) -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($row) { $row.BackupFolder = $target; Add-IndexLine $dest $row }
        Remove-Item -LiteralPath $a.FullName, $log, ([IO.Path]::ChangeExtension($a.FullName, '.json')) -Force -ErrorAction SilentlyContinue
        Write-Output "   OK: $extracted file(s) extracted and counted. Archive deleted from the laptop."
    }
    exit $(if ($bad) { 2 } else { 0 })
}

# ================================================================== reset
$isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
$remoteMode = $Remote -or $isSystem
$oldName = $env:COMPUTERNAME

# --- New name. Refused before anything changes if the name is not one of ours.
$newName = switch -Regex ($oldName) {
    '^(MRQ|MRP|MIP)\d{4}(-.+)$' { "$($Matches[1])7500$($Matches[2])"; break }
    '^(MRM\d{4}-.+|MITLOAN-.+)$' { $oldName; break }
    default { $null }
}
if (-not $newName) {
    Write-Output "STOPPED: '$oldName' is not an MRM / MRQ / MRP / MIP / MITLOAN name. Name it with Setup.bat first. Nothing was changed."
    exit 2
}

# --- Who gets backed up and removed: accounts first, then profiles and folders that belong to no account.
$notProfile = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
$accounts = @(Get-LocalUser | Where-Object { $_.SID.Value -notmatch $builtinRid -and -not (Test-Protected $_.Name) })
$accountSids = @($accounts | ForEach-Object { $_.SID.Value })
$profiles = @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath -like "$env:SystemDrive\Users\*" })
$users = @($accounts | ForEach-Object Name)
$users += @($profiles | Where-Object { $accountSids -notcontains $_.SID -and ($_.SID -notmatch $builtinRid) } | ForEach-Object { Split-Path $_.LocalPath -Leaf } |
    Where-Object { -not (Test-Protected $_) })
$users += @(Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { -not ($_.Attributes -band $notProfile) -and $profiles.LocalPath -notcontains $_.FullName -and -not (Test-Protected $_.Name) } |
    ForEach-Object Name)
$users = @($users | Sort-Object -Unique)
$loaded = @($profiles | Where-Object { $_.Loaded -and $users -contains (Split-Path $_.LocalPath -Leaf) })

# --- Where things go.
if ($remoteMode) {
    $runRoot = Join-Path $offboardLocal "${oldName}_$stamp"
    $archive = "$runRoot.7z"
    $logFile = "$runRoot.log"
} else {
    if (-not $UsbRoot) { $UsbRoot = Split-Path -Qualifier $PSScriptRoot }
    if ($UsbRoot -ieq $env:SystemDrive) {
        Write-Output "STOPPED: no USB given and this script runs from $env:SystemDrive. Pass -UsbRoot <drive>, or -Remote to archive on the laptop. Nothing was changed."
        exit 2
    }
    $usbOffboard = Join-Path $UsbRoot.TrimEnd('\') 'MerionIT-Offboard'
    $runRoot = Join-Path $usbOffboard "${oldName}_$stamp"
    $logFile = Join-Path $runRoot 'Reset-ForNewUser.log'
}

if (-not $dryRun) {
    New-Item -ItemType Directory -Path "$MerionITRoot\logs", (Split-Path $logFile -Parent) -Force -ErrorAction Stop | Out-Null
    $script:logFiles = @($logFile, "$MerionITRoot\logs\Reset-ForNewUser-$stamp.log")
}

Say "Reset-ForNewUser $ScriptVersion, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')$(if ($dryRun) { '   (-WhatIf: nothing is changed)' })"
Say "Mode          : $(if ($remoteMode) { 'remote (archive on the laptop, machine-wide setup)' } else { 'USB (backup to USB, full setup)' })"
Say "Original name : $oldName"
Say "New name      : $newName$(if ($newName -eq $oldName) { '  (kept)' })"
Say "Users         : $(if ($users) { $users -join ', ' } else { '(none besides the protected accounts)' })"
# No agent means it was removed on purpose: it is not reinstalled here. Setup.bat for the new user installs it.
$hasAgent = [bool](Get-Service | Where-Object { $_.DisplayName -like '*Kaseya Agent*' })
Say "Kaseya agent  : $(if ($hasAgent) { 'installed - reinstalled (/r /w) after the reboot so it picks up the new name' } else { 'not installed - left that way, Setup.bat for the new user installs it' })"
Say "Backup        : $(if ($remoteMode) { "$archive  (AES-256, collect at HQ with -Collect)" } else { $runRoot })"

# --- Checks that need no changes made.
$problems = @()
if ($loaded) { $problems += "signed in right now: $(($loaded | ForEach-Object { Split-Path $_.LocalPath -Leaf }) -join ', ') (sign them out or reboot)" }
$sevenZip = Get-SevenZip
if ($remoteMode -and -not $sevenZip) { $problems += '7-Zip not found, so the backup could not be archived' }
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $remoteMode -and -not $SkipRefresh -and -not (Test-Path (Join-Path $repoRoot 'setup\Step1-Accounts-Apps.ps1'))) {
    $problems += "no repo next to this script ($repoRoot) to refresh C:\MerionIT from (use -SkipRefresh to use C:\MerionIT as it is)"
}
$secretsSource = if ((-not $remoteMode) -and (Test-Path (Join-Path $repoRoot 'secrets.psd1'))) { Join-Path $repoRoot 'secrets.psd1' } else { $secretsPath }
if (-not (Get-PcsAdminPassword @($secretsSource))) { $problems += "no PcsAdminPassword in $secretsSource$(if ($remoteMode) { ' (the Kaseya procedure writes it before running this)' })" }
if ($problems -and $dryRun) {
    $problems | ForEach-Object { Say "WOULD STOP: $_" }
} elseif ($problems) {
    $problems | ForEach-Object { Say "STOPPED: $_" }
    Say 'Nothing was changed.'
    exit 2
}

if (-not $dryRun -and -not $Force -and -not $remoteMode) {
    $answer = Read-Host "Back up and REMOVE the users above, rename to $newName and re-run setup? [Y/N]"
    if ($answer -notmatch '^[Yy]') { Say 'Stopped at the prompt. Nothing was changed.'; exit 2 }
}

$exitCode = 0
try {
    # --- 1. Refresh C:\MerionIT (setup scrubs RenamePC / DefaultAccounts after a build).
    if (-not $dryRun -and -not $SkipRefresh) {
        if (-not $remoteMode -and ($repoRoot -ine $MerionITRoot)) {
            Say "Refreshing $MerionITRoot from $repoRoot ..."
            & robocopy.exe $repoRoot $MerionITRoot /E /XD .git MerionIT-Offboard /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "copy from $repoRoot failed (robocopy exit $LASTEXITCODE)" }
        } else {
            Say 'Refreshing C:\MerionIT from GitHub ...'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $bootstrap = Invoke-RestMethod -UseBasicParsing -TimeoutSec 30 'https://raw.githubusercontent.com/cybrwlf/MerionIT/master/bootstrap.ps1'
            & ([scriptblock]::Create($bootstrap)) -NoLaunch *>&1 | Out-Null
            if (-not (Test-Path "$MerionITRoot\setup\DefaultAccounts.ps1")) { throw 'GitHub pull did not restore setup\DefaultAccounts.ps1' }
        }
    }
    if (-not $dryRun -and $secretsSource -ne $secretsPath) { Copy-Item -LiteralPath $secretsSource -Destination $secretsPath -Force }

    # --- 2. Back up and remove each user.
    $backupScript = Get-ChildItem "$MerionITRoot\manual" -Filter 'backup-userfiles-*.ps1' | Sort-Object Name | Select-Object -Last 1
    if (-not $backupScript) { throw "no manual\backup-userfiles-*.ps1 in $MerionITRoot" }
    $backupResults = [ordered]@{}
    foreach ($u in $users) {
        # A name can disappear once an earlier one is removed (a profile folder of an account already done).
        if (-not $dryRun -and -not (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath "$env:SystemDrive\Users\$u")) { continue }
        Say ''
        Say "== Back up and remove $u"
        $bArgs = @{ UserName = $u; Destination = $runRoot; Remove = $true; AllowCloudOnly = $true; IncludeDownloads = $true }
        if ($dryRun) { $bArgs['WhatIf'] = $true } else { $bArgs['Force'] = $true }
        & $backupScript.FullName @bArgs *>&1 | ForEach-Object { Say "   $_" }
        $backupResults[$u] = $LASTEXITCODE
        # backup-userfiles exit codes: 0 = done, 1 = done with cloud-only files left in OneDrive, 2 = problem.
        if ($LASTEXITCODE -ge 2) { throw "backup or removal of $u did not complete (exit $LASTEXITCODE) - stopped before renaming or setup" }
    }
    if ($dryRun) {
        Say ''
        Say "What if: rename $oldName -> $newName, run $(if ($remoteMode) { 'the machine-wide setup' } else { 'Step1-Accounts-Apps.ps1 -Unattended (with Step 2)' }), reboot, then repair the Kaseya agent and run the build check."
        exit 0
    }

    # --- 3. Remote: pack the backup, prove the archive, then drop the plain copy.
    if ($remoteMode -and (Test-Path -LiteralPath $runRoot)) {
        Say ''
        Say "Packing the backup into $archive ..."
        $pw = Get-PcsAdminPassword @($secretsPath)
        & $sevenZip a -t7z -mhe=on -mx=1 "-p$pw" $archive "$runRoot\*" -bso0 -bsp0 2>$null
        $packExit = $LASTEXITCODE
        & $sevenZip t "-p$pw" $archive -bso0 -bsp0 2>$null
        $testExit = $LASTEXITCODE
        $inArchive = Get-ArchiveFileCount $sevenZip $archive $pw
        $onDisk = Get-FileCount $runRoot
        if ($packExit -eq 0 -and $testExit -eq 0 -and $inArchive -eq $onDisk) {
            & cmd.exe /c rd /s /q "$runRoot" 2>&1 | Out-Null
            Say "   Archive tested OK, $inArchive file(s). Plain copy deleted. Collect it at HQ with -Collect."
        } else {
            Say "   WARNING: archive not proven (pack exit $packExit, test exit $testExit, $inArchive of $onDisk file(s)). The plain copy is LEFT in $runRoot."
            $exitCode = 2
        }
    }

    # --- 4. Rename (takes effect at the reboot) and arrange the after-reboot step.
    if ($newName -ne $oldName) {
        if ($hasAgent) {
            Set-Content -Path "$MerionITRoot\.agent-repair-pending" -Value $oldName
        }
        Rename-Computer -NewName $newName -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Say ''
        Say "Renamed $oldName -> $newName (takes effect at the reboot)."
    }
    if ($PSCommandPath -ine $installedCopy) { Copy-Item -LiteralPath $PSCommandPath -Destination $installedCopy -Force }
    @{ OldName = $oldName; NewName = $newName; LogFiles = $script:logFiles } | ConvertTo-Json | Set-Content -LiteralPath $statePath
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$installedCopy`" -AfterReboot"
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Force | Out-Null

    # --- 5. Standards.
    Say ''
    if ($remoteMode) {
        Say '== Machine-wide setup (remote: nobody signed in, so no per-user tweaks)'
        $company = $oldName.Substring(0, 3)
        $steps = [ordered]@{
            'Accounts (pcsadmin, company account)' = { $a = @{ UserName = '' }; if ($company -in 'MRM', 'MRQ', 'MRP', 'MIP') { $a['Company'] = $company }; if ($company -eq 'MRM') { $a['PropertyCode'] = $oldName.Substring(3, 4) }; & "$MerionITRoot\setup\DefaultAccounts.ps1" @a }
            'BGInfo'                               = { & "$MerionITRoot\tweaks\bginfo.ps1" }
            'Apps'                                 = { & "$MerionITRoot\setup\Install-Apps.ps1" }
            'Office'                               = { & "$MerionITRoot\setup\Fix-OfficeLanguages.ps1" }
            'Bloat removal'                        = { & "$MerionITRoot\tweaks\WIN11-removebloat-appx.ps1" }
            'McAfee check'                         = { & "$MerionITRoot\tweaks\remove-mcafee.ps1" }
            'Windows Update cache'                 = { & "$MerionITRoot\tweaks\Clean_win_updates_cache.ps1" }
            'Vendor drivers and Dell extras'       = { & "$MerionITRoot\tweaks\vendor-drivers.ps1" }
            'Power plan'                           = { & cmd.exe /c "$MerionITRoot\setup\powerconfig.cmd" }
            'Windows Update policy'                = { & "$MerionITRoot\tools\Repair-MerionWindowsUpdate.ps1" -AddToReminder }
            'Merion standards'                     = { & "$MerionITRoot\tools\Set-MerionStandards.ps1" }
            'Default profile for the next user'    = { & (Get-ChildItem "$MerionITRoot\tweaks" -Filter 'Set-DefaultUserProfile-*.ps1' | Sort-Object Name | Select-Object -Last 1).FullName }
        }
        foreach ($name in $steps.Keys) {
            Say "-- $name"
            try { & $steps[$name] *>&1 | ForEach-Object { Say "   $_" } } catch { Say "   ERROR: $($_.Exception.Message)"; $exitCode = 2 }
        }
        foreach ($f in 'setup\RenamePC.ps1', 'setup\DefaultAccounts.ps1', 'setup\MITUser.ps1') { Remove-Item -LiteralPath (Join-Path $MerionITRoot $f) -Force -ErrorAction SilentlyContinue }
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss' | Set-Content -Path "$MerionITRoot\.setup-complete"
    } else {
        Say '== Full setup (Step1-Accounts-Apps.ps1 -Unattended, Step 2 follows; close Notepad at the end)'
        $step1Args = @{ Unattended = $true }
        if (-not $hasAgent) { $step1Args['SkipAgent'] = $true }
        & "$MerionITRoot\setup\Step1-Accounts-Apps.ps1" @step1Args *>&1 | ForEach-Object { Say "   $_" }
    }
} catch {
    Say "STOPPED: $($_.Exception.Message)"
    $exitCode = 2
} finally {
    if (-not $dryRun) {
        if (Test-Path -LiteralPath $secretsPath) { Remove-Item -LiteralPath $secretsPath -Force -ErrorAction SilentlyContinue }
        Say "secrets.psd1 in C:\MerionIT: $(if (Test-Path -LiteralPath $secretsPath) { 'STILL THERE - delete it by hand' } else { 'deleted' })"
        # Step 1 -Unattended never deletes it, so it leaves a "delete secrets.psd1" reminder. Drop that line once it is gone.
        $reminder = "$MerionITRoot\setup\Manual-Steps-Reminder.txt"
        if (-not (Test-Path -LiteralPath $secretsPath) -and (Test-Path -LiteralPath $reminder)) {
            $kept = @(Get-Content -LiteralPath $reminder | Where-Object { $_ -notmatch 'Delete C:\\MerionIT\\secrets\.psd1' })
            Set-Content -LiteralPath $reminder -Value $kept
        }
    }
}

# --- 6. Record it. USB: index.csv now. Remote: a .json beside the archive becomes the index line at -Collect.
$row = [pscustomobject]@{
    Date         = Get-Date -Format 'yyyy-MM-dd HH:mm'
    OldName      = $oldName
    NewName      = $newName
    Users        = $users -join '; '
    Mode         = if ($remoteMode) { 'remote' } else { 'usb' }
    BackupFolder = $runRoot
    Result       = if ($exitCode) { 'needs a look - see log' } else { 'ok (build check after reboot is in the log)' }
}
if ($remoteMode) { $row | ConvertTo-Json | Set-Content -LiteralPath "$runRoot.json" } else { Add-IndexLine $usbOffboard $row }

if ($exitCode -and -not (Test-Path $statePath)) { exit $exitCode }
if ($exitCode) {
    Say ''
    Say 'Something needs a look (above). Not rebooting automatically. The after-reboot step still runs at the next restart.'
    exit $exitCode
}
Say ''
Say 'Rebooting in 60 seconds. After the reboot the Kaseya agent is repaired for the new name and the build check is added to this log.'
& shutdown.exe /r /t 60 /c "MerionIT reset: restarting to finish the rename" | Out-Null
exit 0
