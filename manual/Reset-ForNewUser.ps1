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
    DELL. Step 2 runs tweaks\vendor-drivers.ps1, which installs Dell Command Update and only THEN removes
       SupportAssist (removing it first once left a machine with no Dell driver tool). MRQ7588-LT101's
       first reset (2026-11-12) skipped DCU because vendor-drivers.ps1 could only use a copy in
       C:\MerionIT\apps and there was none, so SupportAssist stayed. Since then vendor-drivers.ps1
       downloads the newest DCU for the model from Dell's update catalog, and .NET Desktop Runtime 10
       from Microsoft when missing, each checked against the publisher's hash and signature. So on a
       Dell without DCU this script only checks, before changing anything, that downloads.dell.com (and
       builds.dotnet.microsoft.com, if .NET 10.0.8+ is missing) can be reached. Offline, a Dell-signed
       Dell-Command-Update*.EXE in <repo>\apps, any <USB>\*\apps or C:\MerionIT\apps is copied in and
       used instead. Neither possible = a USB run stops (override: -SkipDellUpdate); remote only warns.
    3. STANDARDS. C:\MerionIT is refreshed first (setup deletes RenamePC/DefaultAccounts after a build, so
       an old copy cannot re-run setup), then:
         USB    : the full setup, setup\Step1-Accounts-Apps.ps1 -Unattended (Step 2 included), no named user.
         Remote : only the parts that apply to the whole machine, because nobody is signed in (Kaseya runs
                  this as SYSTEM): accounts, BGInfo, apps, Office, bloat / McAfee removal, Windows Update
                  cache, vendor drivers, power plan, Windows Update policy, Set-MerionStandards and the
                  Default profile (whoever signs in first gets the per-user settings and taskbar pins from
                  it, as with Add-User.bat). Per-user Start menu / taskbar tweaks are not run.
    4. REBOOT, then a startup task (SYSTEM) UNINSTALLS the Kaseya agent, runs tools\Test-MerionBuild.ps1,
       adds both results to the log and removes itself. A reset laptop goes on the shelf, and a shelved
       machine must not keep an agent (Ricardo, 2026-11-12). Setup.bat for the new user downloads and
       installs it again. Step 1 always gets -SkipAgent, so the build check's kaseya FAIL is expected.
       The uninstall waits for the reboot so a Kaseya-launched remote run is not cut off halfway.
       How: the agent's own uninstall string from Add/Remove Programs with /s added (silent), per Kaseya's
       KB "Uninstall an Agent Via Command Line" (helpdesk.kaseya.com/hc/en-gb/articles/229039368). The
       installer's switch list (help.vsa9.kaseya.com/help/Content/VSA/493.htm) has no uninstall switch.
       Not yet tested on a real machine (2026-11-12): -WhatIf prints the string it would run.

    CLEANUP LIST
      Before anything is changed (right after the Y), one row per user goes into
      <USB>\MerionIT-Offboard\cleanup-list.csv and into the run's own folder: run, date, old and new name,
      serial number, Kaseya agent ID, local user, the Microsoft 365 account that user had OneDrive signed in
      with, and the backup result (updated as each user finishes). KaseyaCleaned and MicrosoftCleaned are
      left blank for Ricardo. It does not record why the user left. Remote: <archive>.cleanup.csv beside
      the archive, merged into the USB list by -Collect.
      The M365 account is read from the user's own registry hive (OneDrive\Accounts\Business*\UserEmail),
      loaded with reg.exe for a moment and unloaded again. If it will not unload the run stops there,
      before any change, because a hive left loaded would block the profile removal.

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
.PARAMETER SkipDellUpdate
    On a Dell, go ahead even though Dell Command Update cannot be installed (offline with no installer
    on the USB, or .NET Desktop Runtime 10.0.8+ missing with Microsoft unreachable). SupportAssist is then left in place, by design of
    tweaks\vendor-drivers.ps1. Without this switch a USB run stops before changing anything.
.PARAMETER Force
    No confirmation prompt. Implied by -Remote.

.EXAMPLE
    E:\MerionIT\manual\Reset-ForNewUser.bat -WhatIf          # same as below, but elevates itself and pauses at the end
    E:\MerionIT\manual\Reset-ForNewUser.ps1 -WhatIf         # from USB: show users, new name, what is copied
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
    [switch]$SkipDellUpdate,
    # Internal: run by the startup task after the reboot.
    [switch]$AfterReboot
)

$ScriptVersion = '2026-11-12.2'
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

# Cleanup list: replace this run's rows in $Path, keep everyone else's (including Ricardo's ticks).
function Merge-CleanupList([string]$Path, $Rows, [string]$RunId) {
    $keep = @()
    if (Test-Path -LiteralPath $Path) { $keep = @(Import-Csv -LiteralPath $Path | Where-Object { $_.Run -ne $RunId }) }
    @($keep) + @($Rows) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
}

# Kaseya agent entries in Add/Remove Programs (what Kaseya's KB uninstalls from), plus its services.
function Get-KaseyaAgent {
    $entries = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } | Where-Object { $_.DisplayName -like '*Kaseya Agent*' -and $_.UninstallString })
    $services = @(Get-Service | Where-Object { $_.DisplayName -like '*Kaseya Agent*' })
    # Kaseya's KB example: ...\Kaseya\<AgentID>\KASetup.exe /s /r /g <AgentID> ...
    $ids = @($entries | ForEach-Object { if ($_.UninstallString -match '/g\s+"?([^"\s]+)') { $Matches[1] } } | Sort-Object -Unique)
    [pscustomobject]@{
        Installed = [bool]($entries -or $services)
        Entries   = $entries
        Id        = if ($ids) { $ids -join '; ' } elseif ($services) { "service $(($services.Name) -join '; ')" } else { '' }
    }
}

# Microsoft 365 account(s) the user had OneDrive signed in with, read from their own NTUSER.DAT.
# reg.exe, not the PowerShell registry provider, which can keep the hive open and block the profile
# removal. Personal OneDrive accounts are skipped on purpose. Throws only if the hive will not unload.
$script:hiveCount = 0
function Get-M365Account([string]$ProfilePath) {
    $hive = Join-Path $ProfilePath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $hive)) { return '(no registry hive)' }
    $script:hiveCount++
    $mount = "HKLM\MerionIT-Reset-$script:hiveCount"
    & reg.exe load $mount $hive 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return '(could not read)' }
    $emails = @()
    try {
        $key = ''
        foreach ($line in @(& reg.exe query "$mount\Software\Microsoft\OneDrive\Accounts" /s /v UserEmail 2>$null)) {
            if ($line -match '^HKEY_') { $key = $line }
            elseif ($key -match '\\Accounts\\Business\d*$' -and $line -match '^\s+UserEmail\s+REG_SZ\s+(\S.*)$') { $emails += $Matches[1].Trim() }
        }
    } finally {
        [GC]::Collect()
        & reg.exe unload $mount 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "could not unload $hive from $mount (reg unload exit $LASTEXITCODE). Reboot before running this again." }
    }
    if ($emails) { ($emails | Sort-Object -Unique) -join '; ' } else { '(none found)' }
}

# The agent's own uninstall string with /s added (silent), per Kaseya's KB. Only runs a KASetup signed
# by Kaseya, or an msiexec /x line (then /qn /norestart). Returns $true when the agent is gone after.
function Invoke-KaseyaUninstall([string]$LogDir) {
    $agent = Get-KaseyaAgent
    if (-not $agent.Installed) { Say '  No Kaseya agent found. Nothing to uninstall.'; return $true }
    if (-not $agent.Entries) { Say '  Kaseya services found but no uninstall entry in Add/Remove Programs. Uninstall it by hand.'; return $false }
    foreach ($e in $agent.Entries) {
        # Expanded here: Start-Process passes %TEMP% (in Kaseya's own /l "%TEMP%\kasetup.log") through literally.
        $cmd = [Environment]::ExpandEnvironmentVariables($e.UninstallString).Trim()
        if ($cmd -match '^"([^"]+)"\s*(.*)$' -or $cmd -match '^(\S+)\s*(.*)$') { $exe = $Matches[1]; $argLine = $Matches[2] } else { continue }
        if ((Split-Path $exe -Leaf) -ieq 'msiexec.exe') {
            if ($argLine -notmatch '(?i)/qn') { $argLine += ' /qn' }
            if ($argLine -notmatch '(?i)/norestart') { $argLine += ' /norestart' }
        } else {
            $sig = Get-AuthenticodeSignature -FilePath $exe -ErrorAction SilentlyContinue
            if (-not $sig -or $sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Kaseya Holdings Inc') {
                Say "  NOT RUN: $exe is missing or not signed by Kaseya (status: $($sig.Status)). Uninstall it by hand."
                return $false
            }
            if ($argLine -notmatch '(?i)(^|\s)/s(\s|$)') { $argLine = "/s $argLine".Trim() }
            if ($argLine -notmatch '(?i)(^|\s)/l(\s|$)') { $argLine += " /l `"$LogDir\kasetup-uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log`"" }
        }
        Say "  Running: `"$exe`" $argLine"
        # Polled, not -Wait (see Agent-Install.ps1: -Wait has hung after a sleep/wake).
        $proc = Start-Process -FilePath $exe -ArgumentList $argLine -PassThru
        $null = $proc.Handle   # keeps the handle so ExitCode is readable afterwards
        $deadline = (Get-Date).AddMinutes(15)
        while ((Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
        if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) { Say '  Uninstaller still running after 15 minutes, not waiting any longer.' }
        else { Say "  Uninstaller exit code: $($proc.ExitCode) (Kaseya does not document these; the check below decides)." }
    }
    for ($i = 0; $i -lt 24; $i++) {
        $left = Get-KaseyaAgent
        if (-not $left.Installed -and -not (Get-CimInstance Win32_Process -Filter "Name = 'AgentMon.exe'" -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Seconds 5
    }
    Say "  Still there after 2 minutes: $(@($left.Entries.DisplayName) + @(Get-Service | Where-Object { $_.DisplayName -like '*Kaseya Agent*' } | ForEach-Object DisplayName) -join ', ')"
    return $false
}

# ================================================================== -AfterReboot (startup task, SYSTEM)
if ($AfterReboot) {
    $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($state) { $script:logFiles = @($state.LogFiles | Where-Object { Test-Path -LiteralPath (Split-Path $_ -Parent) }) }
    Say ''
    Say "== After reboot, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), running as $env:COMPUTERNAME"
    $uninstallMarker = "$MerionITRoot\.agent-uninstall-pending"
    $agentGone = $true
    if (Test-Path -LiteralPath $uninstallMarker) {
        # Give the agent a chance to reach its server first, so the portal can see it go. Not required.
        for ($i = 0; $i -lt 18; $i++) {
            if (Test-NetConnection 'managedsupport.kaseya.net' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue) { break }
            Start-Sleep -Seconds 10
        }
        Say 'Kaseya agent uninstall (this machine goes on the shelf):'
        New-Item -ItemType Directory -Path "$MerionITRoot\logs" -Force | Out-Null
        $agentGone = Invoke-KaseyaUninstall "$MerionITRoot\logs"
        if ($agentGone) {
            Remove-Item -LiteralPath $uninstallMarker -Force
            Say '  Kaseya agent removed. Delete its record in the Kaseya portal (agent ID in cleanup-list.csv).'
        } else {
            Say '  WARNING: the Kaseya agent is still installed. Uninstall it by hand before shelving this machine.'
        }
    }
    Say 'Build check:'
    & "$MerionITRoot\tools\Test-MerionBuild.ps1" | ForEach-Object { Say "  $_" }
    if ($agentGone) { Say '  (kaseya FAIL is expected: no agent on a shelved machine. Setup.bat for the new user installs it.)' }
    if (Test-Path -LiteralPath $secretsPath) { Remove-Item -LiteralPath $secretsPath -Force; Say 'Deleted a leftover secrets.psd1.' }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    Say $(if ($agentGone) { 'Reset finished. Ready for the shelf. Setup.bat for the new user installs the Kaseya agent.' } else { 'Reset finished EXCEPT the Kaseya agent (see above).' })
    exit $(if ($agentGone) { 0 } else { 2 })
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
        $cleanup = [IO.Path]::ChangeExtension($a.FullName, '.cleanup.csv')
        if (Test-Path -LiteralPath $cleanup) {
            $rows = @(Import-Csv -LiteralPath $cleanup)
            Copy-Item -LiteralPath $cleanup -Destination (Join-Path $target 'cleanup-list.csv') -Force
            try { Merge-CleanupList (Join-Path $dest 'cleanup-list.csv') $rows $name; Remove-Item -LiteralPath $cleanup -Force }
            catch { Write-Output "   WARNING: could not add to $dest\cleanup-list.csv (open in Excel?): $($_.Exception.Message). Rows are in $target\cleanup-list.csv." }
        }
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
# A reset machine goes on the shelf: the agent is uninstalled after the reboot. Setup.bat for the new user installs it.
$agent = Get-KaseyaAgent
$hasAgent = $agent.Installed
Say "Kaseya agent  : $(if ($hasAgent) { "installed (ID $($agent.Id)) - UNINSTALLED after the reboot, machine goes on the shelf" } else { 'not installed - left that way, Setup.bat for the new user installs it' })"
if ($hasAgent) {
    foreach ($e in $agent.Entries) { Say "                uninstall string: $($e.UninstallString)" }
    if (-not $agent.Entries) { Say '                WARNING: no uninstall entry in Add/Remove Programs, so the uninstall will have to be done by hand' }
}
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
# --- Dell: Step 2's vendor-drivers.ps1 needs the DCU installer in C:\MerionIT\apps (see DELL above).
$isDell = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer -match 'Dell'
$dcuInstaller = $null
if ($isDell) {
    $dcuCli = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($dcuCli) {
        Say "Dell Cmd Update: already installed ($dcuCli) - Step 2 removes SupportAssist"
    } else {
        # Step 2 downloads DCU fresh from Dell's catalog (and .NET 10 from Microsoft if missing). All this
        # needs is the internet. A Dell-signed copy on the USB is only the offline fallback.
        $canReach = { param($h) [bool](Test-NetConnection $h -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue) }
        $dellOnline = & $canReach 'downloads.dell.com'
        $dotnetDir = "$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App"
        $haveDotnet = [bool](Get-ChildItem $dotnetDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^10\.\d+\.\d+$' -and [version]$_.Name -ge [version]'10.0.8' })
        $dotnetOnline = $haveDotnet -or (& $canReach 'builds.dotnet.microsoft.com')
        if (-not $dellOnline) {
            $dcuDirs = @()
            if (-not $remoteMode) {
                $dcuDirs += Join-Path $repoRoot 'apps'
                $dcuDirs += @(Get-ChildItem "$($UsbRoot.TrimEnd('\'))\*\apps" -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)
            }
            $dcuDirs += "$MerionITRoot\apps"
            foreach ($f in @($dcuDirs | Select-Object -Unique | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter 'Dell-Command-Update*.EXE' -File -ErrorAction SilentlyContinue } | Sort-Object Name -Descending)) {
                $sig = Get-AuthenticodeSignature -FilePath $f.FullName -ErrorAction SilentlyContinue
                if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'Dell') { $dcuInstaller = $f; break }
            }
        }
        $dcuProblem = @()
        if (-not $dellOnline -and -not $dcuInstaller) { $dcuProblem += 'downloads.dell.com is not reachable and there is no Dell Command Update installer on the USB' }
        if (-not $dotnetOnline) { $dcuProblem += '.NET Desktop Runtime 10.0.8+ is not installed and builds.dotnet.microsoft.com is not reachable' }
        if (-not $dcuProblem) {
            $how = if ($dellOnline) { "downloads the newest from Dell's catalog" } else { "installs $($dcuInstaller.FullName) (offline)" }
            Say "Dell Cmd Update: Step 2 $how$(if (-not $haveDotnet) { ' (after installing .NET 10 from Microsoft)' }), then removes SupportAssist"
        } elseif ($SkipDellUpdate -or $remoteMode) {
            Say "Dell Cmd Update: WARNING $($dcuProblem -join '; '). DCU is skipped and SupportAssist stays."
        } else {
            $problems += "Dell Command Update could not be installed: $($dcuProblem -join '; '). Connect to the internet and run again, or run with -SkipDellUpdate to leave DCU out and SupportAssist in"
        }
    }
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

# --- Cleanup list: who was on this machine, for the Kaseya and Microsoft 365 cleanup afterwards.
$runId = "${oldName}_$stamp"
$serial = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
$cleanupRows = [Collections.Generic.List[object]]::new()
try {
    foreach ($u in $users) {
        $p = $profiles | Where-Object { (Split-Path $_.LocalPath -Leaf) -ieq $u } | Select-Object -First 1
        $profilePath = if ($p) { $p.LocalPath } else { "$env:SystemDrive\Users\$u" }
        $m365 = if ($loaded | Where-Object { (Split-Path $_.LocalPath -Leaf) -ieq $u }) { '(signed in, not read)' } else { Get-M365Account $profilePath }
        $cleanupRows.Add([pscustomobject][ordered]@{
                Run              = $runId
                Date             = Get-Date -Format 'yyyy-MM-dd HH:mm'
                OldName          = $oldName
                NewName          = $newName
                Serial           = $serial
                KaseyaAgent      = if ($hasAgent) { $agent.Id } else { '(none installed)' }
                LocalUser        = $u
                M365Account      = $m365
                Backup           = if ($dryRun) { 'what if' } else { 'pending' }
                KaseyaCleaned    = ''
                MicrosoftCleaned = ''
            })
    }
} catch {
    Say "STOPPED: $($_.Exception.Message)"
    Say 'Nothing else was changed.'
    exit 2
}
Say "Serial        : $serial"
Say 'Cleanup list (written before anything changes; backup result filled in as each user finishes):'
if ($cleanupRows.Count) { ($cleanupRows | Format-Table LocalUser, M365Account, KaseyaAgent -AutoSize | Out-String -Width 200).TrimEnd() -split "`r?`n" | ForEach-Object { Say "  $_" } }
else { Say '  (no users, so no rows)' }

if ($remoteMode) { $cleanupTargets = @("$runRoot.cleanup.csv") }
else { $cleanupTargets = @((Join-Path $runRoot 'cleanup-list.csv'), (Join-Path $usbOffboard 'cleanup-list.csv')) }
function Save-CleanupList {
    if ($dryRun) { return }
    foreach ($t in $cleanupTargets) {
        try { Merge-CleanupList $t $cleanupRows $runId }
        catch { Say "WARNING: could not write $t (open in Excel?): $($_.Exception.Message)" }
    }
}
function Set-BackupResult([string]$User, [string]$Result) {
    foreach ($r in $cleanupRows) { if ($r.LocalUser -ieq $User) { $r.Backup = $Result } }
    Save-CleanupList
}

if (-not $dryRun -and -not $Force -and -not $remoteMode) {
    $answer = Read-Host "Back up and REMOVE the users above, rename to $newName and re-run setup? [Y/N]"
    if ($answer -notmatch '^[Yy]') { Say 'Stopped at the prompt. Nothing was changed.'; exit 2 }
}

# Written before the first change. The run's own copy must land, or nothing goes ahead.
if (-not $dryRun -and $cleanupRows.Count) {
    New-Item -ItemType Directory -Path (Split-Path $cleanupTargets[0] -Parent) -Force | Out-Null
    try { Merge-CleanupList $cleanupTargets[0] $cleanupRows $runId }
    catch { Say "STOPPED: could not write the cleanup list $($cleanupTargets[0]): $($_.Exception.Message)"; Say 'Nothing was changed.'; exit 2 }
    Save-CleanupList
    Say "Cleanup list written: $($cleanupTargets -join ' and ')"
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
    # Dell Command Update installer where vendor-drivers.ps1 (Step 2) looks for it. Checked by hash.
    if ($dcuInstaller -and -not $dryRun) {
        $dcuTarget = Join-Path "$MerionITRoot\apps" $dcuInstaller.Name
        if ($dcuInstaller.FullName -ine $dcuTarget) {
            New-Item -ItemType Directory -Path "$MerionITRoot\apps" -Force | Out-Null
            Say "Copying $($dcuInstaller.Name) to $MerionITRoot\apps for Step 2 ..."
            Copy-Item -LiteralPath $dcuInstaller.FullName -Destination $dcuTarget -Force
            if ((Get-FileHash -LiteralPath $dcuTarget).Hash -ne (Get-FileHash -LiteralPath $dcuInstaller.FullName).Hash) {
                throw "copy of $($dcuInstaller.Name) to $MerionITRoot\apps does not match the original"
            }
        }
    }

    # --- 2. Back up and remove each user.
    $backupScript = Get-ChildItem "$MerionITRoot\manual" -Filter 'backup-userfiles-*.ps1' | Sort-Object Name | Select-Object -Last 1
    if (-not $backupScript) { throw "no manual\backup-userfiles-*.ps1 in $MerionITRoot" }
    $backupResults = [ordered]@{}
    foreach ($u in $users) {
        # A name can disappear once an earlier one is removed (a profile folder of an account already done).
        if (-not $dryRun -and -not (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath "$env:SystemDrive\Users\$u")) {
            Set-BackupResult $u 'already gone (removed with an earlier name)'
            continue
        }
        Say ''
        Say "== Back up and remove $u"
        $bArgs = @{ UserName = $u; Destination = $runRoot; Remove = $true; AllowCloudOnly = $true; IncludeDownloads = $true }
        if ($dryRun) { $bArgs['WhatIf'] = $true } else { $bArgs['Force'] = $true }
        & $backupScript.FullName @bArgs *>&1 | ForEach-Object { Say "   $_" }
        $backupResults[$u] = $LASTEXITCODE
        # backup-userfiles exit codes: 0 = done, 1 = done with cloud-only files left in OneDrive, 2 = problem.
        if (-not $dryRun) {
            Set-BackupResult $u $(switch ($backupResults[$u]) {
                    0 { 'backed up + removed' }
                    1 { 'backed up + removed; cloud-only files left in OneDrive (see cloud-only-files.txt)' }
                    default { "FAILED (exit $_) - see log" }
                })
        }
        if ($backupResults[$u] -ge 2) { throw "backup or removal of $u did not complete (exit $($backupResults[$u])) - stopped before renaming or setup" }
    }
    if ($dryRun) {
        Say ''
        Say "What if: rename $oldName -> $newName, run $(if ($remoteMode) { 'the machine-wide setup' } else { 'Step1-Accounts-Apps.ps1 -Unattended (with Step 2)' }), reboot, then $(if ($hasAgent) { 'uninstall the Kaseya agent and ' })run the build check."
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
    # The agent comes off after the reboot (it goes on the shelf), so no rename repair is wanted.
    Remove-Item -LiteralPath "$MerionITRoot\.agent-repair-pending" -Force -ErrorAction SilentlyContinue
    if ($hasAgent) { Set-Content -Path "$MerionITRoot\.agent-uninstall-pending" -Value $oldName }
    if ($newName -ne $oldName) {
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
        # Always -SkipAgent: the agent is uninstalled after the reboot, Setup.bat for the new user installs it.
        $step1Args = @{ Unattended = $true; SkipAgent = $true }
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

# Anyone the run never reached (it stopped first) is marked so in the cleanup list.
if (-not $dryRun -and @($cleanupRows | Where-Object Backup -eq 'pending')) {
    foreach ($r in $cleanupRows) { if ($r.Backup -eq 'pending') { $r.Backup = 'not done - run stopped (see log)' } }
    Save-CleanupList
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
Say "Rebooting in 60 seconds. After the reboot $(if ($hasAgent) { 'the Kaseya agent is uninstalled and ' })the build check is added to this log."
& shutdown.exe /r /t 60 /c "MerionIT reset: restarting to finish the rename" | Out-Null
exit 0
