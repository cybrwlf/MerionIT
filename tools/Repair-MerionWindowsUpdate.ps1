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

.PARAMETER AddToReminder
    Write any findings into C:\MerionIT\Manual-Steps-Reminder.txt, which opens in Notepad at the end
    of 2nd_Step/3rd_Step. This is how provisioning checks its own work: the recurring failure across
    this toolkit has been scripts reporting success without verifying it, and a machine should not
    be able to leave IT with a broken update policy that nobody saw. Off by default so a fleet sweep
    does not write to disk on every machine it measures.

.EXAMPLE
    powershell.exe -ExecutionPolicy Unrestricted -File .\Repair-MerionWindowsUpdate.ps1 -ReportOnly

.EXAMPLE
    powershell.exe -ExecutionPolicy Unrestricted -File .\Repair-MerionWindowsUpdate.ps1
#>
param([switch]$ReportOnly, [switch]$AddToReminder)

# Bump this on every change that alters output or behaviour. It is echoed in the RESULT line so a
# fleet sweep can prove which version produced a given result - raw.githubusercontent.com caches
# for several minutes, and a stale copy on one endpoint otherwise looks like a real difference
# between machines. Cost us a confused round trip on 2026-09-23.
$ScriptVersion = '2026-09-23.3'

$ReminderPath = "C:\MerionIT\Manual-Steps-Reminder.txt"
function Add-ReminderIfMissing {
    param([string]$Line)
    if (-not (Test-Path $ReminderPath)) { return }
    if (Select-String -Path $ReminderPath -Pattern ([regex]::Escape($Line)) -Quiet) { return }
    $content = @(Get-Content -Path $ReminderPath)
    if ($content.Count -gt 0 -and $content[-1] -match '^=+$') {
        $newContent = $content[0..($content.Count - 2)] + $Line + $content[-1]
    } else {
        $newContent = $content + $Line
    }
    Set-Content -Path $ReminderPath -Value $newContent
}

$wu     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au     = "$wu\AU"
$issues = New-Object System.Collections.Generic.List[string]
$acted  = New-Object System.Collections.Generic.List[string]

# Write-Output, not Write-Host, on purpose. This script's primary caller is Kaseya running it as
# SYSTEM with nobody logged on. Write-Host goes to the information stream; a remote-execution
# harness that collects the pipeline rather than the console would silently capture nothing, and a
# diagnostic that returns an empty result is worse than one that fails. Write-Output lands on the
# success stream, which every harness collects, and still prints normally in a console.
function Say($m) { Write-Output $m }

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
    (Get-ItemProperty $wu | Select-Object * -Exclude PS*) | Format-List | Out-String | Write-Output
} else { Say "  (no WindowsUpdate policy key)" }
if (Test-Path $au) {
    Say "  AU subkey:"
    (Get-ItemProperty $au | Select-Object * -Exclude PS*) | Format-List | Out-String | Write-Output
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
$dcuOk     = $false
if (Test-Path $dcuCli) {
    if ($ReportOnly) {
        # -ReportOnly must not change anything, and `/configure` IS a write - it would set DCU's
        # schedule on a machine we are only measuring. Fall back to the service state, which is
        # the failure mode actually seen in the field (MRM8035-LT101, 2026-09-23): dcu-cli
        # present and correct, DellClientManagementService Stopped/Disabled, every call exit 2.
        $svc = Get-Service DellClientManagementService -ErrorAction SilentlyContinue
        if (-not $svc)                    { $dcuHealth = 'present, service MISSING' }
        elseif ($svc.Status -ne 'Running'){ $dcuHealth = "present, service $($svc.Status)/$($svc.StartType) - LIKELY BROKEN" }
        else                              { $dcuHealth = 'present, service running (not probed - report mode)'; $dcuOk = $true }
    }
    else {
        # Presence is not health. Only a real invocation proves dcu-cli works.
        & $dcuCli /configure -scheduleManual -silent 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 2) { $dcuHealth = 'BROKEN (exit 2)' }
        else                     { $dcuHealth = 'working'; $dcuOk = $true }
    }
}
$haveExclude = (Get-ItemProperty $wu -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue).ExcludeWUDriversInQualityUpdate

if ($isDell) {
    Say "Dell : dcu-cli $dcuHealth"
    if ($dcuOk) {
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

# Surface anything still wrong to the technician. In repair mode most findings have just been
# fixed, so only report what a human still has to act on - currently the DCU case, which this
# script deliberately will not fix itself (that is tweaks\vendor-drivers.ps1's job).
if ($AddToReminder) {
    $needsHuman = $issues | Where-Object { $_ -match '^ACTION NEEDED' -or $ReportOnly }
    foreach ($i in $needsHuman) {
        Add-ReminderIfMissing "[ ] Windows Update check: $i"
    }
    if ($needsHuman) { Say "  (added $($needsHuman.Count) item(s) to Manual-Steps-Reminder.txt)" }
}

if (-not $ReportOnly) {
    Say ""
    Say "--- CHANGES ---"
    if ($acted.Count -eq 0) { Say "  none" } else { $acted | ForEach-Object { Say "  - $_" } }

    Say ""
    Say "--- AFTER ---"
    (Get-ItemProperty $wu | Select-Object * -Exclude PS*) | Format-List | Out-String | Write-Output
    Say "  AU subkey present: $(Test-Path $au)   (should be False)"
}

# Single machine-readable line, for collecting across a fleet sweep.
#
# OS family is called out explicitly because DisplayVersion alone is ambiguous - "22H2" is both
# Windows 10 22H2 (build 19045) and Windows 11 22H2 (build 22621), and only the build number
# separates them. Counting Windows 10 machines is a direct cost question (they are past end of
# support and on paid ESU), so it should not depend on reading build numbers by eye.
$osFamily = if ([int]$cv.CurrentBuild -ge 22000) { 'win11' } else { 'win10-EOL' }
Say ""
Say ("RESULT|{0}|{1}|{2}|{3} {4}.{5}|{6}|issues={7}|mode={8}|v={9}" -f `
        $env:COMPUTERNAME, $mfr, $osFamily,
        $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR,
        $(if ($isDell) { "dcu=$dcuHealth" } else { 'dcu=n/a' }),
        $issues.Count, $(if ($ReportOnly) { 'report' } else { 'repair' }), $ScriptVersion)
