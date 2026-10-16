#Requires -RunAsAdministrator
<#
.SYNOPSIS
    New user at an already-set-up desk: create the account, then do what full setup would have done
    for them, then put the checklist for the human on screen.

.DESCRIPTION
    Add-User.bat runs this. Full setup (Setup.bat) configures the machine and the setup account.
    Adding a user afterwards used to do only the account, so the new person got plain Windows defaults
    and nothing told the tech what was still manual. This closes that gap:

      1. Creates the account (SingleUser.ps1, which prompts for the temporary password).
      2. Seeds the Default profile with the per-user settings and taskbar pins
         (tweaks\Set-DefaultUserProfile-*.ps1, newest one). Runs before the user's first logon,
         which is the only time a profile picks them up. Safe to repeat.
      3. Checks the machine-wide things a new user depends on, and repairs only what is known to break:
           - BGInfo: Users must be able to run C:\BGinfo\Bginfo.exe, or the startup entry fails
             silently for every account except the one that ran setup (repaired if not).
           - Kaseya agent, Huntress, Windows Update policy, Location: reported, never changed.
      4. Makes manual\New-User-Reminder.txt open in Notepad once, the first time the new user signs in.

    If the account already has a profile (it has signed in before), that profile is left alone: the
    Default profile only reaches NEW profiles. Run tweaks\Set-DefaultUserProfile-*.ps1 -UserName <name>
    while that user is signed out if their existing profile needs the settings.

.PARAMETER UserName
    The local account to add. Asked for if not given.

.PARAMETER SkipProfileSeed
    Skip step 2.

.NOTES
    Exit code: 0 = done, nothing needs attention
               1 = done, but a check above reported WARN
               2 = the account could not be created, or the profile seeding did not verify
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$UserName,
    [switch]$SkipProfileSeed
)

$ErrorActionPreference = 'Continue'
$ScriptVersion = '2026-10-16.3'
$MerionRoot = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $MerionRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$warns = 0
$failed = $false

function Say($m) { Write-Output $m }
function Warn($m) { $script:warns++; Write-Output "WARN  $m" }

if (-not $UserName) { $UserName = (Read-Host -Prompt 'Local account name to add').Trim() }
if (-not $UserName) { Say 'No user name given. Nothing was done.'; exit 2 }

$log = Join-Path $logDir "Prepare-NewUser-$stamp.log"
try { Start-Transcript -Path $log -Force | Out-Null } catch { }

Say "Prepare-NewUser $ScriptVersion on $env:COMPUTERNAME for '$UserName', $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Say ''

# ---- 1. The account -------------------------------------------------------------------------------
Say '== 1. Account'
$hadProfileBefore = $false
$existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if ($existing) {
    $hadProfileBefore = [bool](Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $existing.SID.Value })
}
& (Join-Path $PSScriptRoot 'SingleUser.ps1') -UserName $UserName
if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
    Say "ERROR  account '$UserName' does not exist, so nothing below was done."
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
Say "OK    account '$UserName' exists."
if ($hadProfileBefore) {
    Warn "'$UserName' already has a profile. It is untouched. To give it the standard settings, sign them out and run tweaks\Set-DefaultUserProfile-*.ps1 -UserName $UserName"
}

# ---- 2. Default profile ---------------------------------------------------------------------------
Say ''
Say '== 2. Default profile (settings and taskbar pins for new profiles)'
if ($SkipProfileSeed) {
    Say 'Skipped (-SkipProfileSeed).'
} else {
    $seed = Get-ChildItem (Join-Path $MerionRoot 'tweaks') -Filter 'Set-DefaultUserProfile-*.ps1' -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -Last 1
    if (-not $seed) {
        Warn "tweaks\Set-DefaultUserProfile-*.ps1 not found. Run Update-Scripts.bat, then add the user again, or the new profile gets plain Windows defaults."
    } else {
        Say "Using $($seed.Name)"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $seed.FullName
        if ($LASTEXITCODE -ne 0) {
            Say "ERROR  the profile seeding reported a problem (exit $LASTEXITCODE). The new user may start with plain Windows defaults."
            $failed = $true
        }
    }
}

# ---- 3. Machine checks ----------------------------------------------------------------------------
Say ''
Say '== 3. Machine checks'

# BGInfo: the startup entry is machine-wide, but winget leaves Bginfo.exe runnable only by the account
# that installed it, so local admins (filtered token at logon) never got the background.
$bgDir = 'C:\BGinfo'; $bgExe = Join-Path $bgDir 'Bginfo.exe'
if (Test-Path -LiteralPath $bgExe) {
    $usersSid = 'S-1-5-32-545'
    $canRun = { (Get-Acl -LiteralPath $bgExe).Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $usersSid -and
        ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ExecuteFile) } }
    if (& $canRun) {
        Say 'OK    BGInfo: Users can run Bginfo.exe.'
    } else {
        Say 'FIX   BGInfo: Users cannot run Bginfo.exe, so it would not start for this account. Repairing permissions (same as tweaks\bginfo.ps1).'
        & icacls.exe $bgDir /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
        & icacls.exe $bgDir /inheritance:r | Out-Null
        & icacls.exe "$bgDir\*" /reset /T /C | Out-Null
        if (& $canRun) { Say 'OK    BGInfo: repaired, Users can run Bginfo.exe.' } else { Warn 'BGInfo permissions could not be repaired.' }
    }
} else {
    Say 'INFO  BGInfo is not installed on this machine (C:\BGinfo\Bginfo.exe missing).'
}

# BGInfo second pass: redraw after the new profile has finished its first-run work (see tweaks\bginfo.ps1).
if (Test-Path -LiteralPath $bgExe) {
    if (Get-ScheduledTask -TaskName 'MerionIT BGInfo second pass' -ErrorAction SilentlyContinue) {
        Say 'OK    BGInfo second-pass task is registered.'
    } else {
        Say 'FIX   BGInfo second-pass task is missing, so a new profile loses the background at first sign-in. Registering it.'
        $BgInfoDir = $bgDir; $bgInfoExe = Get-Item -LiteralPath $bgExe
        $bgTaskName = 'MerionIT BGInfo second pass'
        $bgAction = New-ScheduledTaskAction -Execute $bgInfoExe.FullName -Argument "`"$BgInfoDir\BGinfo.bgi`" /silent /timer:0 /nolicprompt"
        $bgTrigger = New-ScheduledTaskTrigger -AtLogOn
        $bgTrigger.Delay = 'PT90S'
        $bgPrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
        $bgSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName $bgTaskName -Action $bgAction -Trigger $bgTrigger -Principal $bgPrincipal -Settings $bgSettings -Description 'Re-draws BGInfo 90 s after logon, after Windows first-run work on a new profile has finished.' -Force | Out-Null
        if (Get-ScheduledTask -TaskName $bgTaskName -ErrorAction SilentlyContinue) { Say 'OK    BGInfo second-pass task registered.' } else { Warn 'BGInfo second-pass task could not be registered.' }
    }
}

$kas = @(Get-Service | Where-Object { $_.DisplayName -like 'Kaseya Agent*' -or $_.Name -like 'KAPRCMPS*' })
if ($kas | Where-Object { $_.Status -eq 'Running' }) { Say 'OK    Kaseya agent service is running (confirm the machine in the portal).' }
else { Warn 'Kaseya agent service not found running. The machine may not be reporting to the portal.' }

$hun = @(Get-Service | Where-Object { $_.DisplayName -like 'Huntress*' })
if ($hun | Where-Object { $_.Status -eq 'Running' }) { Say 'OK    Huntress is running.' }
else { Say 'INFO  Huntress service not found running (not installed here, or stopped).' }

if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU') {
    Warn 'Windows Update policy key (AU) is present. The old provisioning disabled updates; see tools\Repair-MerionWindowsUpdate.ps1 -ReportOnly.'
} else { Say 'OK    No Windows Update AU policy key.' }

$loc = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -ErrorAction SilentlyContinue).Value
if ($loc -eq 'Allow') { Say 'OK    Location is allowed machine-wide. A new user still starts with "let apps access" off (per-user setting).' }
else { Warn "Machine-wide Location consent is '$loc', expected Allow. See tools\Set-MerionStandards.ps1 -ReportOnly." }

# ---- 4. The reminder ------------------------------------------------------------------------------
Say ''
Say '== 4. Reminder'
$template = Join-Path $PSScriptRoot 'New-User-Reminder.txt'
if (Test-Path -LiteralPath $template) {
    Say 'OK    The checklist opens in Notepad once, the first time the new user signs in (set in the Default profile).'
} else {
    Warn "manual\New-User-Reminder.txt not found, so no checklist will open at first sign-in. Run Update-Scripts.bat."
}
Say ''
$exit = if ($failed) { 2 } elseif ($warns -gt 0) { 1 } else { 0 }
Say "Done. Warnings: $warns. Exit code $exit.  Log: $log"
try { Stop-Transcript | Out-Null } catch { }
exit $exit
