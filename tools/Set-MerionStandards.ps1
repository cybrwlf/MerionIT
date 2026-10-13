#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bring an already-deployed Merion machine up to the current provisioning standards without
    re-running setup. Safe via Kaseya as SYSTEM, safe to re-run, safe on a machine in use.

.DESCRIPTION
    Provisioning (tweaks\basic10-11stuff.ps1, tweaks\WIN11-removebloat-appx.ps1) only reaches a machine
    when it is built. This applies the changes that matter to machines already out there, for every
    user on them, without touching Start menu, taskbar, accounts, apps or anything else.

    Two standards, both decided 2026-10-09:

    1. LOCATION IS ALLOWED.
       Earlier builds denied it. Sets the machine-wide consent to Allow, removes the DisableLocation
       policy (a value of 1 overrides the consent setting and greys the toggle out), sets the sensor
       override to 1, sets the Geolocation service config Status to 1, and makes sure the service
       is not Disabled. Machine-wide (HKLM) only: per-user consent under HKCU is not touched.

    2. THE "CALENDAR" WINDOW IS GONE.
       Microsoft.M365Companions launches Calendar.exe /minimize at logon. Removed for ALL existing
       users and deprovisioned so new users do not get it. The provisioning script only removes it
       for the user running the script, which is why existing users keep it.
       It can come back with an Office / Microsoft 365 Apps update. Re-run this if it does.

    Every change is verified by reading the value back afterwards. "No error" is not the test.

.PARAMETER ReportOnly
    Change nothing. Report what is out of standard. Use for a fleet sweep.

.NOTES
    Writes with Write-Output, not Write-Host, because Kaseya runs this as SYSTEM with nobody logged
    on and Write-Host output can be lost there. Needs no user, no profile and no internet.
    Exit code: 0 = in standard (or fixed and verified), 2 = something is still out of standard.
#>
param(
    [switch]$ReportOnly
)

$ScriptVersion = '2026-10-13.1'
function Say($m) { Write-Output $m }

$consentPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
$policyPath  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
$sensorPath  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}'
$lfsvcConfig = 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'
$calPackage  = 'Microsoft.M365Companions'

$issues = 0     # things found out of standard
$stillBad = 0   # things still out of standard after the run

function Get-LocationState {
    $svc = Get-Service -Name lfsvc -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Consent         = (Get-ItemProperty $consentPath -ErrorAction SilentlyContinue).Value
        DisableLocation = (Get-ItemProperty $policyPath -ErrorAction SilentlyContinue).DisableLocation
        DisableProvider = (Get-ItemProperty $policyPath -ErrorAction SilentlyContinue).DisableWindowsLocationProvider
        DisableScripting = (Get-ItemProperty $policyPath -ErrorAction SilentlyContinue).DisableLocationScripting
        Sensor         = (Get-ItemProperty $sensorPath -ErrorAction SilentlyContinue).SensorPermissionState
        Status          = (Get-ItemProperty $lfsvcConfig -ErrorAction SilentlyContinue).Status
        StartType       = if ($svc) { [string]$svc.StartType } else { 'missing' }
    }
}
function Test-LocationOk($s) {
    ($s.Consent -eq 'Allow') -and ($null -eq $s.DisableLocation) -and ($null -eq $s.DisableProvider) -and ($null -eq $s.DisableScripting) -and ($s.Sensor -eq 1) -and
    ($s.Status -eq 1) -and ($s.StartType -ne 'Disabled')
}
function Format-LocationState($s) {
    "consent=$($s.Consent) DisableLocation=$(if ($null -eq $s.DisableLocation) { 'not set' } else { $s.DisableLocation }) DisableProvider=$(if ($null -eq $s.DisableProvider) { 'not set' } else { $s.DisableProvider }) DisableScripting=$(if ($null -eq $s.DisableScripting) { 'not set' } else { $s.DisableScripting }) sensor=$($s.Sensor) lfsvcStatus=$($s.Status) lfsvc=$($s.StartType)"
}

function Get-CalendarState {
    [pscustomobject]@{
        # -ErrorAction Stop on purpose: if these cannot be read (not elevated, Appx service down), an
        # empty result must not be reported as "not present". Caught by the caller as UNKNOWN.
        Installed   = @(Get-AppxPackage -AllUsers -Name $calPackage -ErrorAction Stop)
        Provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $calPackage })
    }
}

Say "=========================================================="
Say " Merion machine standards"
Say "=========================================================="
Say "Host    : $env:COMPUTERNAME"
Say "Script  : v$ScriptVersion"
Say "Mode    : $(if ($ReportOnly) { 'REPORT ONLY - nothing will be changed' } else { 'apply' })"
Say ""

# ---------------------------------------------------------------- 1. Location
Say "--- LOCATION (target: allowed) ---"
$loc = Get-LocationState
Say "Before  : $(Format-LocationState $loc)"
$locResult = 'ok'
if (Test-LocationOk $loc) {
    Say "OK   already in standard"
} else {
    $issues++
    if ($ReportOnly) {
        Say "FIND out of standard - would be changed"
        $locResult = 'out-of-standard'
    } else {
        try {
            if (-not (Test-Path $consentPath)) { New-Item -Path $consentPath -Force | Out-Null }
            Set-ItemProperty -Path $consentPath -Name 'Value' -Type String -Value 'Allow' -ErrorAction Stop
            Remove-ItemProperty -Path $policyPath -Name 'DisableLocation','DisableWindowsLocationProvider','DisableLocationScripting' -ErrorAction SilentlyContinue
            if (-not (Test-Path $sensorPath)) { New-Item -Path $sensorPath -Force | Out-Null }
            Set-ItemProperty -Path $sensorPath -Name 'SensorPermissionState' -Type DWord -Value 1 -ErrorAction Stop
            if (-not (Test-Path $lfsvcConfig)) { New-Item -Path $lfsvcConfig -Force | Out-Null }
            Set-ItemProperty -Path $lfsvcConfig -Name 'Status' -Type DWord -Value 1 -ErrorAction Stop
            $svc = Get-Service -Name lfsvc -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -eq 'Disabled') { Set-Service -Name lfsvc -StartupType Manual -ErrorAction Stop }
        } catch {
            Say "FAIL $($_.Exception.Message)"
        }
        $loc = Get-LocationState
        Say "After   : $(Format-LocationState $loc)"
        if (Test-LocationOk $loc) {
            Say "FIXED and verified by read-back"
            $locResult = 'fixed'
        } else {
            Say "STILL OUT OF STANDARD after the change. Something else (Intune/GPO) may be re-applying a policy. Needs a human."
            $locResult = 'STILL-BAD'
            $stillBad++
        }
    }
}
Say ""

# ---------------------------------------------------------------- 2. Calendar
Say "--- CALENDAR (Microsoft.M365Companions, target: gone) ---"
$calResult = 'ok'
$cal = $null
try { $cal = Get-CalendarState }
catch {
    Say "FAIL could not read package state: $($_.Exception.Message)"
    $calResult = 'UNKNOWN'
    $stillBad++
}
if ($cal) {
$users = @($cal.Installed | ForEach-Object { $_.PackageUserInformation } | ForEach-Object { "$($_.UserSecurityId.UserName)" } | Where-Object { $_ } | Sort-Object -Unique)
Say "Before  : installed for $($cal.Installed.Count) package(s), users: $(if ($users) { $users -join ', ' } else { 'none' }); provisioned: $($cal.Provisioned.Count)"
if (($cal.Installed.Count -eq 0) -and ($cal.Provisioned.Count -eq 0)) {
    Say "OK   not present"
} else {
    $issues++
    if ($ReportOnly) {
        Say "FIND present - would be removed for all users and deprovisioned"
        $calResult = 'present'
    } else {
        foreach ($p in $cal.Installed) {
            try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
            catch { Say "FAIL remove $($p.PackageFullName): $($_.Exception.Message)" }
        }
        foreach ($p in $cal.Provisioned) {
            try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null }
            catch { Say "FAIL deprovision $($p.PackageName): $($_.Exception.Message)" }
        }
        # A copy already running keeps showing until logoff; end it so nobody sees it again today.
        Get-Process -Name Calendar -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -like "*$calPackage*" } |
            ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Say "Stopped running Calendar.exe (pid $($_.Id))" }
        try { $cal = Get-CalendarState } catch { $cal = $null }
        if ($cal) { Say "After   : installed for $($cal.Installed.Count) package(s); provisioned: $($cal.Provisioned.Count)" }
        if ($cal -and ($cal.Installed.Count -eq 0) -and ($cal.Provisioned.Count -eq 0)) {
            Say "FIXED and verified by read-back"
            $calResult = 'fixed'
        } else {
            Say "STILL PRESENT (or could not be read back) after removal. Needs a human."
            $calResult = 'STILL-BAD'
            $stillBad++
        }
    }
}
}
Say ""

$mode = if ($ReportOnly) { 'report' } else { 'apply' }
Say ("RESULT|{0}|location={1}|calendar={2}|issues={3}|stillbad={4}|mode={5}|v={6}" -f $env:COMPUTERNAME, $locResult, $calResult, $issues, $stillBad, $mode, $ScriptVersion)

if ($stillBad -gt 0) { exit 2 }
exit 0
