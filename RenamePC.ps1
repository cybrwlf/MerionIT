#Requires -RunAsAdministrator
<#
Consolidated replacement for MRMrenamePC.ps1 / MRQrenamePC.ps1 / MRPrenamePC.ps1 / MITrenamePC.ps1.
Behavior per company:
  - MRM / MRQ / MRP: prompt for a 4-digit property/phone-extension code.
  - MIT: property is always "Loan" (annual MIT-event loaner laptops), no property prompt.

Desktop-vs-laptop is auto-detected for every company (battery presence + chassis type, same
signals validated in research/Test-MachineDetection.ps1 - matched 100% of known machine types
across the field data collected so far), falling back to the manual prompt only if those signals
don't clearly agree. Before 2026-08-14 this only ran for MRM - MRQ/MRP/MIT were hardcoded to "LT"
on the assumption those companies never buy desktops. Switched to detecting it for all four
companies instead of assuming, so a real MRQ/MRP/MIT desktop (if one ever shows up) gets named
correctly rather than mislabeled "LT".

Purchase year is also auto-detected for every company (CPU generation vs. OS install date), same
idea as machine type - see the "Year Purchased" section below for the exact rule and its known
~60% accuracy in the 1-3 year-gap band (confirmed against research/MachineDetection-Log.csv on
2026-08-14). Accepted anyway: the final "Is <name> correct?" prompt below is the same safety net
already relied on for machine type, and this is strictly better than the old fully-manual entry.

The CPU-generation-to-year table is copied inline from research/IntelGenYears.csv rather than read
from that file, because research/ isn't deployed to C:\MerionIT by bootstrap.ps1 (IntelGenYears.csv
is a *.csv, and *.csv is gitignored repo-wide - see .gitignore). If IntelGenYears.csv is ever
updated, update the $GenYearTable below to match by hand.

Full context on how the purchase-year rule was derived and verified (the real machine-by-machine
data behind the "~60% in the 1-3 gap band" figure above, and what's still unproven) lives in
research/Year-Detection-Decision.md.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('MRM', 'MRQ', 'MRP', 'MIT')]
    [string]$Company
)

if ($Company -eq 'MIT') {
    $property = "Loan"
} else {
    $property = Read-Host "Property or Phone Extension Number? [4 digit]"
}

# Auto-detect desktop vs. laptop for every company, using the same battery+chassis signals
# validated in research/Test-MachineDetection.ps1 (100% match against known machine types
# across the field data collected so far). Falls back to the manual prompt for the same
# ambiguous cases that script flags for review (e.g. a UPS-backed desktop reporting a battery).
$LaptopChassisCodes = 8, 9, 10, 14, 30, 31, 32
$DesktopChassisCodes = 3, 4, 5, 6, 7, 13, 15, 16

$battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
$hasBattery = [bool]$battery

$enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue
$chassisCode = $enclosure.ChassisTypes | Select-Object -First 1
$chassisSaysLaptop = $chassisCode -in $LaptopChassisCodes
$chassisSaysDesktop = $chassisCode -in $DesktopChassisCodes

$ambiguous = ($hasBattery -and $chassisSaysDesktop) -or (-not $chassisSaysLaptop -and -not $chassisSaysDesktop)

if ($ambiguous) {
    Write-Warning "Couldn't auto-detect machine type reliably (battery present: $hasBattery, chassis code: $chassisCode) - enter it manually."
    $machinetype = Read-Host "Desktop or Laptop? [DT/LT]"
} else {
    $machinetype = if ($hasBattery -or $chassisSaysLaptop) { "LT" } else { "DT" }
    Write-Host "Detected machine type: $machinetype (battery present: $hasBattery, chassis code: $chassisCode)"
}


# Auto-detect purchase year: compare the CPU's generation-launch year against the OS install
# date. Rule (decided 2026-08-14, verified against 8 real machines in
# research/MachineDetection-Log.csv):
#   - Gap of 0 (they agree)      -> use that year, no ambiguity.
#   - Gap of 1-3 (normal buying lag - we typically buy a year or few after a CPU launches)
#                                -> use the OS install year.
#   - Gap can't be determined, or >3 (usually a rebuild/reimage on older reused hardware,
#     confirmed in the field: MITLOAN-LT801 showed a 7-year gap from exactly this) -> fall back
#     to asking the tech, same as before.
# Known limitation, accepted: 2 of the 8 real machines checked had a "normal-looking" gap of 2
# that was actually caused by a later reimage on a same-year purchase, not real buying lag - the
# 1-3 rule got those wrong. Caught by the final Y/N confirmation below, same safety net already
# used for machine type.
$GenYearTable = @{
    '2'      = @{ Laptop = 2011; Desktop = 2011 }
    '3'      = @{ Laptop = 2012; Desktop = 2012 }
    '4'      = @{ Laptop = 2013; Desktop = 2013 }
    '5'      = @{ Laptop = 2014; Desktop = 2014 }
    '6'      = @{ Laptop = 2015; Desktop = 2015 }
    '7'      = @{ Laptop = 2016; Desktop = 2016 }
    '8'      = @{ Laptop = 2018; Desktop = 2017 }
    '9'      = @{ Laptop = 2019; Desktop = 2018 }
    '10'     = @{ Laptop = 2019; Desktop = 2020 }
    '11'     = @{ Laptop = 2020; Desktop = 2021 }
    '12'     = @{ Laptop = 2022; Desktop = 2021 }
    '13'     = @{ Laptop = 2023; Desktop = 2022 }
    '14'     = @{ Laptop = 2023; Desktop = 2023 }
    'Ultra1' = @{ Laptop = 2023; Desktop = 2023 }
    'Ultra2' = @{ Laptop = 2024; Desktop = 2024 }
    'Ultra3' = @{ Laptop = 2026; Desktop = 2026 }
}

$cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$cpuName = $cpu.Name

$genMatch = [regex]::Match($cpuName, '(\d+)(?:st|nd|rd|th)\s+Gen')
$ultraMatch = [regex]::Match($cpuName, 'Ultra\s+\d+\s+(\d)\d{2}')
$modelMatch = [regex]::Match($cpuName, 'i[3579]-(\d{4,5})')

$genKey = $null
if ($genMatch.Success) {
    $genKey = $genMatch.Groups[1].Value
} elseif ($ultraMatch.Success) {
    $genKey = "Ultra$($ultraMatch.Groups[1].Value)"
} elseif ($modelMatch.Success) {
    $digits = $modelMatch.Groups[1].Value
    $twoDigitPrefix = [int]$digits.Substring(0, 2)
    $oneDigitPrefix = [int]$digits.Substring(0, 1)
    if ($twoDigitPrefix -ge 10 -and $twoDigitPrefix -le 14) {
        $genKey = "$twoDigitPrefix"
    } elseif ($oneDigitPrefix -ge 2 -and $oneDigitPrefix -le 9) {
        $genKey = "$oneDigitPrefix"
    }
}

$cpuYear = $null
if ($genKey -and $GenYearTable.ContainsKey($genKey)) {
    $cpuYear = if ($machinetype -eq 'DT') { $GenYearTable[$genKey].Desktop } else { $GenYearTable[$genKey].Laptop }
}

$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$osInstallYear = if ($os.InstallDate) { $os.InstallDate.Year } else { $null }

$autoYear = $null
if ($cpuYear -and $osInstallYear) {
    $yearGap = $osInstallYear - $cpuYear
    if ($yearGap -eq 0) {
        $autoYear = $cpuYear
        Write-Host "Detected purchase year: $autoYear (CPU launch year and OS install year agree - CPU: `"$cpuName`")"
    } elseif ($yearGap -ge 1 -and $yearGap -le 3) {
        $autoYear = $osInstallYear
        Write-Host "Detected purchase year: $autoYear (OS install year, $yearGap year(s) after CPU launch year $cpuYear - normal buying lag - CPU: `"$cpuName`")"
    } else {
        Write-Warning "CPU launch year ($cpuYear) and OS install year ($osInstallYear) differ by $yearGap years - too large to trust automatically (likely a rebuild/reimage on older hardware). Enter the purchase year manually."
    }
} else {
    Write-Warning "Couldn't determine both CPU launch year and OS install year for this machine (CPU: `"$cpuName`") - enter the purchase year manually."
}

if ($autoYear) {
    $yearpurchased = "$autoYear"
} else {
    $yearpurchased = Read-Host "Year Purchased? [e.g. 2024/2025/2026]"
}
$yearsingle = $yearpurchased.Substring($yearpurchased.Length - 1)
$individual = Read-Host "Unique ID 01,02,03? [1/2/3]"

$NewPCName = "$Company$property-$machinetype$yearsingle" + "0$individual"

Write-Host $NewPCName

$namecheck = (Read-Host "Is `"$NewPCName`" correct? [Y/N]").ToUpper()

if ($namecheck -eq 'Y') {
    # Try to auto-resume 1st_Step.ps1 after the reboot this rename requires, so the
    # tech doesn't have to remember to log back in and re-run it manually. If this
    # doesn't fire reliably in the field, the old manual "log back in and re-run"
    # process still works exactly as before.
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
            -Name "MerionITResume" `
            -Value 'powershell.exe -ExecutionPolicy Unrestricted -File C:\MerionIT\1st_Step.ps1' `
            -ErrorAction Stop
        Write-Host "RunOnce resume set - 1st_Step.ps1 will relaunch automatically after reboot."
    } catch {
        Write-Warning "Could not set RunOnce resume ($($_.Exception.Message)). After reboot, log back in and re-run 1st_Step.ps1 manually to verify the rename took."
    }

    Rename-Computer -NewName $NewPCName
    Restart-Computer
} else {
    Write-Warning "Name not changed"
}
