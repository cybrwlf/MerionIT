#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bring a Merion machine's Windows Update policy to the current standard. Safe to run via Kaseya
    as SYSTEM, safe to re-run, and safe to run on a machine that is already correct.

.DESCRIPTION
    Repairs the three things provisioning got wrong on machines built before 2026-09-22. All three
    were found on real machines, not theorised:

    1. WINDOWS UPDATE SWITCHED OFF ENTIRELY.
       The old basic10-11stuff.ps1 wrote NoAutoUpdate=1 and AUOptions=1 under ...\WindowsUpdate\AU.
       Machines were not pinned to an old build - they were told never to look. MRM8035-LT101 was
       found on 2026-09-23 sitting at a June 2024 patch level after two years of daily use at a
       property. Every machine provisioned with that script carries the same two values.

    2. THE "MANAGED BY YOUR ORGANIZATION" BANNER.
       Comes from NoAutoRebootWithLoggedOnUsers under the same AU key - NOT from the deferral
       values, which is what we assumed for a long time. Removing the AU key removes the banner
       and keeps the deferral.

    3. WINDOWS UPDATE OFFERING DRIVERS IT CAN NEVER INSTALL.
       See tools\Diag-WindowsUpdate.ps1 and the MRM8035-LT101 findings. On Dell, DCU owns drivers,
       so WU driver offers are noise - superseded versions and drivers for absent hardware that
       pile up in the pending list and produce a permanent, false "restart required". On every
       other vendor WU is the ONLY driver path and must stay free to offer them.

    VENDOR LOGIC, and why it is conditional rather than blanket:
       Dell + working dcu-cli   -> ExcludeWUDriversInQualityUpdate = 1   (DCU has drivers covered)
       Dell + broken/absent DCU -> leave WU drivers ON, and say so loudly. Suppressing WU drivers
                                   on a machine with no working DCU leaves it with no driver path
                                   at all. That exact hole was created on MRM8035-LT101.
       Anything else            -> ensure the value is CLEARED.

.PARAMETER ReportOnly
    Change nothing. Report current state and what would be changed. Use this for the fleet sweep -
    it answers "how many machines are affected" without touching any of them.

.EXAMPLE
    powershell.exe -ExecutionPolicy Unrestricted -File .\Repair-MerionWindowsUpdate.ps1 -ReportOnly

.EXAMPLE
    powershell.exe -ExecutionPolicy Unrestricted -File .\Repair-MerionWindowsUpdate.ps1
#>
param([switch]$ReportOnly)

$wu     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au     = "$wu\AU"
$issues = New-Object System.Collections.Generic.List[string]
$acted  = New-Object System.Collections.Generic.List[string]

function Say($m) { Write-Host $m }

$cv     = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$mfr    = (Get-CimInstance Win32_ComputerSystem).Manufacturer
$model  = (Get-CimInstance Win32_ComputerSystem).Model
$isDell = $mfr -match 'Dell'

Say "=========================================================="
Say " Merion Windows Update repair$(if ($ReportOnly) {'  [REPORT ONLY - no changes]'})"
Say "=========================================================="
Say "Host    : $env:COMPUTERNAME"
Say "Vendor  : $mfr / $model"
Say "OS      : $($cv.DisplayVersion)  build $($cv.CurrentBuild).$($cv.UBR)"
Say ""

# ---------------------------------------------------------------- current state
Say "--- BEFORE ---"
if (Test-Path $wu) {
    (Get-ItemProperty $wu | Select-Object * -Exclude PS*) | Format-List | Out-String | Write-Host
} else { Say "  (no WindowsUpdate policy key)" }
if (Test-Path $au) {
    Say "  AU subkey:"
    (Get-ItemProperty $au | Select-Object * -Exclude PS*) | Format-List | Out-String | Write-Host
} else { Say "  (no AU subkey - good)" }


# ------------------------------------------- 1. the AU subkey should not exist
# Everything Merion needs lives directly under WindowsUpdate. The AU subkey only ever holds the
# values that broke things: NoAutoUpdate, AUOptions, NoAutoRebootWithLoggedOnUsers.
if (Test-Path $au) {
    $auVals = Get-ItemProperty $au
    if ($auVals.NoAutoUpdate -eq 1 -or $auVals.AUOptions -eq 1) {
        $issues.Add("CRITICAL: automatic updates disabled (NoAutoUpdate=$($auVals.NoAutoUpdate), AUOptions=$($auVals.AUOptions)) - this machine has not been patching")
    }
    if ($auVals.NoAutoRebootWithLoggedOnUsers -eq 1) {
        $issues.Add("'Managed by your organization' banner source present (NoAutoRebootWithLoggedOnUsers=1)")
    }
    if (-not $ReportOnly) {
        Remove-Item $au -Recurse -Force -ErrorAction SilentlyContinue
        $acted.Add("removed the AU subkey")
    }
} else {
    Say "OK   AU subkey absent"
}


# ------------------------------------------------- 2. the deferral values
if (-not (Test-Path $wu)) {
    if (-not $ReportOnly) { New-Item $wu -Force | Out-Null }
}
$cur = Get-ItemProperty $wu -ErrorAction SilentlyContinue

foreach ($v in @(
    @{ Name='DeferQualityUpdatesPeriodInDays'; Want=7;  Why='7-day quality deferral - lets Microsoft pull a bad update before it reaches Merion' }
    @{ Name='BranchReadinessLevel';            Want=16; Why='16 = General Availability Channel' }
)) {
    $have = $cur.($v.Name)
    if ($have -ne $v.Want) {
        $issues.Add("$($v.Name) is '$have', should be $($v.Want) ($($v.Why))")
        if (-not $ReportOnly) {
            Set-ItemProperty $wu -Name $v.Name -Type DWord -Value $v.Want
            $acted.Add("set $($v.Name)=$($v.Want)")
        }
    } else {
        Say "OK   $($v.Name) = $have"
    }
}


# ------------------------------------------ 3. driver offers, vendor-dependent
$dcuCli    = "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
$dcuHealth = 'absent'
if (Test-Path $dcuCli) {
    # Presence is not health. A partial uninstall leaves the binary while removing Dell Core
    # Services, and every dcu-cli call then returns 2.
    & $dcuCli /configure -scheduleManual -silent 2>&1 | Out-Null
    $dcuHealth = if ($LASTEXITCODE -eq 2) { 'BROKEN (exit 2)' } else { 'working' }
}
$haveExclude = (Get-ItemProperty $wu -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue).ExcludeWUDriversInQualityUpdate

if ($isDell) {
    Say "Dell : dcu-cli $dcuHealth"
    if ($dcuHealth -eq 'working') {
        if ($haveExclude -ne 1) {
            $issues.Add("WU is offering drivers on a Dell with working DCU - expect phantom driver updates and a false 'restart required'")
            if (-not $ReportOnly) {
                Set-ItemProperty $wu -Name ExcludeWUDriversInQualityUpdate -Type DWord -Value 1
                $acted.Add("set ExcludeWUDriversInQualityUpdate=1 (DCU owns drivers)")
            }
        } else { Say "OK   ExcludeWUDriversInQualityUpdate = 1" }
    }
    else {
        $issues.Add("ACTION NEEDED: Dell Command Update is $dcuHealth - this machine has no OEM driver path. Leaving Windows Update free to offer drivers until DCU is fixed. Run tweaks\vendor-drivers.ps1.")
        if ($haveExclude -eq 1 -and -not $ReportOnly) {
            Remove-ItemProperty $wu -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue
            $acted.Add("cleared ExcludeWUDriversInQualityUpdate - DCU is not working, WU must stay available")
        }
    }
}
else {
    if ($haveExclude -eq 1) {
        $issues.Add("Non-Dell with WU driver offers suppressed - this machine has NO driver path")
        if (-not $ReportOnly) {
            Remove-ItemProperty $wu -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue
            $acted.Add("cleared ExcludeWUDriversInQualityUpdate - WU is the driver path on non-Dell")
        }
    } else { Say "OK   WU free to offer drivers (correct for $mfr)" }
}


# --------------------------------------------------------------- 4. services
foreach ($s in 'wuauserv','bits') {
    $svc = Get-Service $s -ErrorAction SilentlyContinue
    if (-not $svc) { $issues.Add("$s service missing"); continue }
    if ($svc.StartType -eq 'Disabled') {
        $issues.Add("$s is Disabled")
        if (-not $ReportOnly) {
            Set-Service $s -StartupType Automatic
            Start-Service $s -ErrorAction SilentlyContinue
            $acted.Add("re-enabled $s")
        }
    } else { Say "OK   $s $($svc.Status)/$($svc.StartType)" }
}


# ----------------------------------------------------------------- summary
Say ""
Say "--- FINDINGS ---"
if ($issues.Count -eq 0) { Say "  none - this machine was already correct" }
else { $issues | ForEach-Object { Say "  * $_" } }

if (-not $ReportOnly) {
    Say ""
    Say "--- CHANGES ---"
    if ($acted.Count -eq 0) { Say "  none" } else { $acted | ForEach-Object { Say "  - $_" } }

    Say ""
    Say "--- AFTER ---"
    (Get-ItemProperty $wu | Select-Object * -Exclude PS*) | Format-List | Out-String | Write-Host
    Say "  AU subkey present: $(Test-Path $au)   (should be False)"
}

# Single machine-readable line, for collecting across a fleet sweep.
Say ""
Say ("RESULT|{0}|{1}|{2}|{3}|issues={4}|mode={5}" -f `
        $env:COMPUTERNAME, $mfr, "$($cv.DisplayVersion) $($cv.CurrentBuild).$($cv.UBR)",
        $(if ($isDell) { "dcu=$dcuHealth" } else { 'dcu=n/a' }),
        $issues.Count, $(if ($ReportOnly) { 'report' } else { 'repair' }))
