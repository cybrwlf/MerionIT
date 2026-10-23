#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Back up a former user's Desktop, Documents and Pictures (and their OneDrive folder) whether or
    not OneDrive had taken those folders over, and optionally remove the user afterwards.

.DESCRIPTION
    Rewritten 2026-10-13. The previous version copied whatever top-level profile folders were not on
    an exclude list with Copy-Item and -ErrorAction SilentlyContinue. It only caught OneDrive-
    redirected folders by accident, hid every failure, and had no way to tell a complete backup
    from a partial one.

    BACKUP
      No -UserName : every profile under C:\Users except operator*, administrator*, TempUser*,
                     PCSadmin*, public*, scan* and defaultuser*.
      -UserName    : that user only (matched by account SID, or by profile folder name when the
                     account is already gone).

      Per user it copies:
        - Desktop, Documents, Pictures from where they REALLY are. The location is read from the
          user's own registry hive (User Shell Folders), so a folder OneDrive moved to
          "OneDrive - <tenant>\Desktop" or one redirected elsewhere is found. The plain
          C:\Users\<user>\Desktop etc. are copied too when they still exist, because Known Folder
          Move can leave files behind in them.
        - Every OneDrive* folder in the profile, whole. A known folder that lives inside one is
          not copied a second time.
        - Downloads, only with -IncludeDownloads.

      Lands in <Destination>\users\<profile folder>\<yyyy-MM-dd_HHmmss>\, one dated folder per run,
      so a second run never overwrites the first. Copied with robocopy (no ACLs, so whoever picks
      the backup up can read it).

      Every source is then verified with a second, list-only robocopy pass: anything it would still
      copy did not make it. Each of those files is classed as either
        - cloud-only: a OneDrive Files On-Demand placeholder. Its content is not on this disk and
          cannot be downloaded here, because the former user's OneDrive is not signed in. Listed in
          cloud-only-files.txt. These exist ONLY in the user's Microsoft 365 OneDrive.
        - not copied: a real failure (locked, unreadable, disk full). Listed in not-copied-files.txt.

    REMOVE (-Remove, named user only)
      Runs only after that user's backup verified with nothing in "not copied". Cloud-only files
      also block it unless -AllowCloudOnly is given. Then:
        - deletes the Windows profile through Win32_UserProfile (folder and ProfileList entry),
        - deletes a leftover C:\Users\<user> folder Windows no longer tracks, if one matched,
        - deletes the local account,
        - reads all three back to confirm they are gone,
        - reports (does not change) scheduled tasks and an auto-logon still naming the user.
      Refused for the excluded names above and for a user who is still signed in.
      Asks before each deletion unless -Force is given. -WhatIf wins over -Force.

.PARAMETER Destination
    Backup root. Default C:\MerionIT\backup (bootstrap.ps1 never touches it). Point it at a USB
    drive or share to get the copy off the machine being reassigned.

.EXAMPLE
    .\backup-userfiles-20261013-2319.ps1                          # back up everyone, remove nobody
    .\backup-userfiles-20261013-2319.ps1 jdoe                     # back up jdoe
    .\backup-userfiles-20261013-2319.ps1 jdoe -Remove -WhatIf     # show what would be copied and removed
    .\backup-userfiles-20261013-2319.ps1 jdoe -Remove             # back up, verify, ask, remove
    powershell.exe -ExecutionPolicy Bypass -File C:\MerionIT\manual\backup-userfiles-20261013-2319.ps1 jdoe -Remove -Force -Destination E:\Offboard   # unattended (Kaseya)

.NOTES
    Writes with Write-Output, not Write-Host, because Kaseya runs this as SYSTEM with nobody logged
    on and Write-Host output can be lost there. The same lines go to
    <Destination>\backup-userfiles-<timestamp>.log.
    Exit code: 0 = everything copied and verified (and removed, if asked)
               1 = copied and verified, but cloud-only files were found and left behind
               2 = something was not copied, or a removal was refused or did not complete
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Position = 0)]
    [string]$UserName,

    [string]$Destination = 'C:\MerionIT\backup',

    # After a verified backup, remove the named user's profile and local account.
    [switch]$Remove,

    # Remove without asking. This, not -Confirm:$false, is the unattended switch: powershell.exe -File
    # passes "$false" as text and the run dies on it before anything happens.
    [switch]$Force,

    # Let -Remove go ahead even though cloud-only OneDrive files could not be backed up.
    [switch]$AllowCloudOnly,

    [switch]$IncludeDownloads
)

$ScriptVersion = '2026-10-13.1'
$Protected = 'operator*', 'administrator*', 'TempUser*', 'PCSadmin*', 'public*', 'scan*', 'defaultuser*'
$Destination = $Destination.TrimEnd('\')
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$dryRun = [bool]$WhatIfPreference
# Loaded up front with WhatIf switched off: auto-loading them under -WhatIf prints a "Set Alias" line per alias.
$WhatIfPreference = $false
Import-Module CimCmdlets, Microsoft.PowerShell.LocalAccounts, ScheduledTasks -ErrorAction SilentlyContinue
$WhatIfPreference = $dryRun

# Helper functions return values, so only script-level code calls Say (Write-Output inside a
# function would end up in its return value).
$logFile = $null
function Say($m) {
    Write-Output $m
    if ($logFile) { Add-Content -LiteralPath $logFile -Value $m }
}

function Test-Protected([string]$Name) {
    [bool]($Protected | Where-Object { $Name -like $_ })
}

# Where the user's shell folders really point, read from THEIR hive (ours would give our own).
# Returns a hashtable; a missing key means "not recorded", and the caller falls back to the default.
function Get-ShellFolderPaths {
    param([string]$ProfilePath, [string]$Sid, [bool]$Loaded)

    $valueNames = @{
        Desktop   = 'Desktop'
        Documents = 'Personal'
        Pictures  = 'My Pictures'
        Downloads = '{374DE290-123F-4565-9164-39C4925E467B}'
    }
    $result = @{}

    $mounted = $null
    if ($Loaded -and $Sid) {
        $root = $Sid
    } else {
        $mounted = "MerionBackup_$PID"
        & reg.exe load "HKU\$mounted" (Join-Path $ProfilePath 'NTUSER.DAT') 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $result['_HiveError'] = $true
            return $result
        }
        $root = $mounted
    }

    try {
        $key = [Microsoft.Win32.Registry]::Users.OpenSubKey("$root\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders")
        if ($key) {
            foreach ($name in $valueNames.Keys) {
                # Unexpanded on purpose: %USERPROFILE% has to become the target's profile, not ours.
                $raw = $key.GetValue($valueNames[$name], $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($raw) {
                    $result[$name] = ([string]$raw -ireplace '%USERPROFILE%', $ProfilePath.Replace('$', '$$')).TrimEnd('\')
                }
            }
            $key.Close()
        }
    } finally {
        if ($mounted) {
            # An open handle keeps the hive mounted, and a mounted hive blocks profile removal.
            $key = $null
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg.exe unload "HKU\$mounted" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $result['_UnloadError'] = $true }
        }
    }
    $result
}

# Copy pass returns robocopy's exit code. List-only pass returns the files robocopy would still
# copy, read back from a Unicode log so non-ASCII file names survive.
# /XJD keeps out of directory junctions (the hidden "My Music"-style loops). Not /XJ or /XJF:
# OneDrive files are reparse points, and those switches could skip them from both passes.
function Invoke-Robocopy {
    param([string]$Source, [string]$Target, [string]$Log, [switch]$ListOnly)

    $roboArgs = @($Source, $Target, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:0', '/W:0', '/XJD', '/FFT', '/NP')
    if ($ListOnly) {
        $roboArgs += '/L', '/XX', '/NJH', '/NJS', '/NDL', '/NC', '/NS', '/FP', "/UNILOG:$Log"
        & robocopy.exe @roboArgs | Out-Null
        return @(Get-Content -LiteralPath $Log -Encoding Unicode -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $roboArgs += "/UNILOG+:$Log"
    & robocopy.exe @roboArgs | Out-Null
    $LASTEXITCODE
}

# Offline (0x1000), RecallOnOpen (0x40000), RecallOnDataAccess (0x400000): the content is not on disk.
# An unreadable path answers $false on purpose, so it is counted as a failure, not excused.
function Test-CloudOnly([string]$Path) {
    $p = if ($Path.Length -ge 248 -and $Path -notlike '\\*') { "\\?\$Path" } else { $Path }
    try { $attr = [int][System.IO.File]::GetAttributes($p) } catch { return $false }
    [bool]($attr -band 0x441000)
}

# ---- Guards that need no work done first --------------------------------------------------------
if ($Remove -and -not $UserName) {
    throw '-Remove needs a user name. Running without one backs up every user and removes nobody.'
}
if ($Remove -and (Test-Protected $UserName)) {
    throw "'$UserName' is on the protected list ($($Protected -join ', ')) - refusing to remove it."
}

# ---- Find the profiles --------------------------------------------------------------------------
$usersRoot = Join-Path $env:SystemDrive 'Users'
$profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
    Where-Object { -not $_.Special -and $_.LocalPath -like "$usersRoot\*" } |
    ForEach-Object {
        [pscustomobject]@{
            Name   = Split-Path $_.LocalPath -Leaf
            Path   = $_.LocalPath.TrimEnd('\')
            Sid    = $_.SID
            Loaded = [bool]$_.Loaded
        }
    })
# A folder under C:\Users that Windows has no profile entry for can still hold someone's files.
Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $profiles.Path -notcontains $_.FullName } |
    ForEach-Object {
        $profiles += [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Sid = $null; Loaded = $false }
    }

$account = $null
if ($UserName) {
    $account = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    $targets = @($profiles | Where-Object { ($account -and $_.Sid -eq $account.SID.Value) -or $_.Name -ieq $UserName })
    if (-not $targets -and -not $account) {
        Write-Warning "No local account and no profile found for '$UserName' - nothing to do."
        exit 2
    }
} else {
    $targets = @($profiles | Where-Object { -not (Test-Protected $_.Name) })
}

if ($Remove -and ($targets | Where-Object Loaded)) {
    throw "'$UserName' is still signed in (profile loaded). Sign them out or reboot, then re-run. Nothing was copied or removed."
}
foreach ($t in $targets) {
    if ("$Destination\" -like "$($t.Path)\*") {
        throw "Destination '$Destination' is inside the profile being backed up ($($t.Path))."
    }
}

if (-not $dryRun) {
    New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
    $logFile = Join-Path $Destination "backup-userfiles-$stamp.log"
}

Say "backup-userfiles $ScriptVersion on $env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Say "Destination: $Destination$(if ($dryRun) { '   (-WhatIf: nothing is copied or removed)' })"
Say "Users: $(if ($targets) { $targets.Name -join ', ' } else { '(none)' })"

# ---- Backup -------------------------------------------------------------------------------------
$wanted = @('Desktop', 'Documents', 'Pictures')
if ($IncludeDownloads) { $wanted += 'Downloads' }

$failedTotal = 0
$cloudTotal = 0

foreach ($t in $targets) {
    Say ''
    Say "== $($t.Name)  ($($t.Path))$(if ($t.Loaded) { '  [signed in]' })"
    $failed = @()
    $cloud = @()

    if (-not (Test-Path -LiteralPath $t.Path -PathType Container)) {
        Say '   Profile folder does not exist - nothing to back up.'
        continue
    }

    $shell = Get-ShellFolderPaths -ProfilePath $t.Path -Sid $t.Sid -Loaded $t.Loaded
    if ($shell['_HiveError']) {
        Say "   WARNING: could not read this user's registry hive, so a redirected folder outside the profile would be missed. Using the default locations."
    }
    if ($shell['_UnloadError']) {
        Say "   WARNING: this user's registry hive is still mounted as HKU\MerionBackup_$PID. A removal will fail until it is unloaded (reg unload) or the machine reboots."
    }

    # Backup folder name -> source path. OneDrive first, so known folders inside it are not repeated.
    $sources = [ordered]@{}
    $oneDriveDirs = @(Get-ChildItem -LiteralPath $t.Path -Directory -Filter 'OneDrive*' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName })
    foreach ($od in $oneDriveDirs) { $sources[(Split-Path $od -Leaf)] = $od }

    foreach ($w in $wanted) {
        $default = Join-Path $t.Path $w
        foreach ($candidate in @($default, $shell[$w]) | Where-Object { $_ }) {
            if ($sources.Values -contains $candidate) { continue }
            if ($oneDriveDirs | Where-Object { "$candidate\" -like "$_\*" }) {
                Say "   $w is inside OneDrive ($candidate) - covered by the OneDrive copy."
                continue
            }
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                if ($candidate -ine $default) {
                    Say "   NOT REACHABLE: $w is redirected to $candidate and that path cannot be opened from here."
                    $failed += $candidate
                }
                continue
            }
            $sources[$(if ($candidate -ieq $default) { $w } else { "$w-redirected" })] = $candidate
        }
    }

    if ($sources.Count -eq 0 -and -not $failed) {
        Say '   No Desktop, Documents, Pictures or OneDrive folder found - nothing to back up.'
        continue
    }

    $runDir = Join-Path $Destination "users\$($t.Name)\$stamp"
    if ($dryRun) {
        $verifyLog = Join-Path $env:TEMP "backup-userfiles-whatif-$PID.log"
    } else {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
        $verifyLog = Join-Path $runDir 'verify.log'
    }

    foreach ($name in $sources.Keys) {
        $src = $sources[$name]
        $dst = Join-Path $runDir $name

        if ($dryRun) {
            $pending = Invoke-Robocopy -Source $src -Target $dst -Log $verifyLog -ListOnly
            $pendingCloud = @($pending | Where-Object { Test-CloudOnly $_ }).Count
            Say "   What if: copy $src -> $dst  ($($pending.Count) files, $pendingCloud of them cloud-only and not copyable)"
            continue
        }

        Say "   Copying $src"
        $rc = Invoke-Robocopy -Source $src -Target $dst -Log (Join-Path $runDir 'robocopy.log')

        # The exit code is not the test. Ask robocopy what it would STILL copy: that did not make it.
        $left = Invoke-Robocopy -Source $src -Target $dst -Log $verifyLog -ListOnly
        $leftCloud = @($left | Where-Object { Test-CloudOnly $_ })
        $leftFailed = @($left | Where-Object { $leftCloud -notcontains $_ })
        $cloud += $leftCloud
        $failed += $leftFailed
        Say "     robocopy exit $rc; verify: $($leftFailed.Count) not copied, $($leftCloud.Count) cloud-only"
    }

    if ($dryRun) {
        Remove-Item -LiteralPath $verifyLog -Force -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue
        continue
    }

    if ($cloud) { Set-Content -LiteralPath (Join-Path $runDir 'cloud-only-files.txt') -Value $cloud -Encoding UTF8 }
    if ($failed) { Set-Content -LiteralPath (Join-Path $runDir 'not-copied-files.txt') -Value $failed -Encoding UTF8 }

    # Informational only (paths over 260 characters are skipped by this count, not by the backup).
    $inBackup = Get-ChildItem -LiteralPath $runDir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -ne $runDir } | Measure-Object -Property Length -Sum
    Say "   Backup: $runDir  (~$($inBackup.Count) files, ~$([math]::Round($inBackup.Sum / 1GB, 2)) GB)"

    if ($failed) {
        Say "   FAILED: $($failed.Count) item(s) not copied - see not-copied-files.txt"
    }
    if ($cloud) {
        Say "   CLOUD-ONLY: $($cloud.Count) file(s) are OneDrive placeholders with no content on this disk - see cloud-only-files.txt."
        Say "               They exist only in this user's Microsoft 365 OneDrive. Recover them there before the account is deleted."
    }
    if (-not $failed -and -not $cloud) { Say '   OK: everything copied and verified.' }

    $failedTotal += $failed.Count
    $cloudTotal += $cloud.Count
}

# ---- Remove -------------------------------------------------------------------------------------
$removeProblem = $false
if ($Remove) {
    Say ''
    Say "== Remove $UserName"

    if ($failedTotal) {
        Say "   REFUSED: $failedTotal item(s) were not backed up. Nothing was removed."
        $removeProblem = $true
    } elseif ($cloudTotal -and -not $AllowCloudOnly) {
        Say "   REFUSED: $cloudTotal cloud-only file(s) could not be backed up. Nothing was removed."
        Say '            Recover them from the user''s OneDrive first, or re-run with -AllowCloudOnly to remove anyway.'
        $removeProblem = $true
    } else {
        if ($dryRun) { Say '   -WhatIf: the backup was listed, not made, so nothing below was verified.' }

        foreach ($t in $targets) {
            try {
                if ($t.Sid) {
                    # Fetched again: the backup may have run for a long time since the first look.
                    $userProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($t.Sid)'" -ErrorAction Stop
                    if (-not $userProfile) { continue }
                    if ($userProfile.Loaded) { throw "profile $($t.Path) is loaded (the user signed in during the backup)" }
                    if (($Force -and -not $dryRun) -or $PSCmdlet.ShouldProcess($t.Path, 'Delete Windows user profile (folder and ProfileList registry entry)')) {
                        Remove-CimInstance -InputObject $userProfile -Confirm:$false -ErrorAction Stop
                        Say "   Removed profile $($t.Path)."
                    }
                } elseif (($Force -and -not $dryRun) -or $PSCmdlet.ShouldProcess($t.Path, 'Delete leftover profile folder (no ProfileList entry)')) {
                    # rd, not Remove-Item -Recurse: rd deletes a junction itself and does not walk into its target.
                    & cmd.exe /c rd /s /q "$($t.Path)" 2>&1 | Out-Null
                    Say "   Removed leftover folder $($t.Path)."
                }
            } catch {
                Say "   ERROR removing $($t.Path): $($_.Exception.Message)"
                $removeProblem = $true
            }
        }

        if ($account) {
            try {
                if (($Force -and -not $dryRun) -or $PSCmdlet.ShouldProcess($UserName, 'Delete local user account')) {
                    Remove-LocalUser -Name $UserName -Confirm:$false -ErrorAction Stop
                    Say "   Removed local account $UserName."
                }
            } catch {
                Say "   ERROR removing account ${UserName}: $($_.Exception.Message)"
                $removeProblem = $true
            }
        }

        if (-not $dryRun) {
            # Read it back. "No error" is not the test.
            foreach ($t in $targets) {
                if (Test-Path -LiteralPath $t.Path) {
                    Say "   STILL PRESENT: folder $($t.Path)"
                    $removeProblem = $true
                }
                if ($t.Sid -and (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($t.Sid)")) {
                    Say "   STILL PRESENT: ProfileList entry $($t.Sid)"
                    $removeProblem = $true
                }
            }
            if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
                Say "   STILL PRESENT: local account $UserName"
                $removeProblem = $true
            }
            if (-not $removeProblem) { Say "   Verified: no profile folder, no ProfileList entry, no local account for $UserName." }

            # Reported, not changed: someone has to decide what these should run as.
            $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.Principal.UserId -ieq $UserName -or $_.Principal.UserId -like "*\$UserName" })
            foreach ($task in $tasks) { Say "   NOTE: scheduled task still set to run as this user: $($task.TaskPath)$($task.TaskName)" }
            $winlogon = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
            if ($winlogon.AutoAdminLogon -eq '1' -and $winlogon.DefaultUserName -ieq $UserName) {
                Say '   NOTE: Windows auto-logon is still configured for this user (Winlogon AutoAdminLogon / DefaultUserName).'
            }
        }
    }
}

# ---- Result -------------------------------------------------------------------------------------
Say ''
$exitCode = if ($failedTotal -or $removeProblem) { 2 } elseif ($cloudTotal) { 1 } else { 0 }
Say "Done. Not copied: $failedTotal. Cloud-only left behind: $cloudTotal. Exit code $exitCode.$(if ($logFile) { "  Log: $logFile" })"
exit $exitCode
