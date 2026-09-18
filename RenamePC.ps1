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

Every prompt below also has a matching optional parameter. Supply them and the script runs with
no console input at all, which is what makes it usable over a remote/SYSTEM session (Kaseya, SSH)
where Read-Host has no interactive token to read from. Omit them and the behavior is exactly as
before. This exists for machine *reassignments* - a machine that already has a Merion name and is
being handed to a new user - which the old flow couldn't do remotely at all.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('MRM', 'MRQ', 'MRP', 'MIT')]
    [string]$Company,

    # 4-digit property code / phone extension. Ignored for MIT (always "Loan").
    [ValidatePattern('^\d{4}$')]
    [string]$Property,

    # Overrides battery/chassis auto-detection.
    [ValidateSet('DT', 'LT')]
    [string]$MachineType,

    # 4-digit purchase year. Highest-priority year source - beats both the existing-name
    # digit and CPU/OS-install detection below.
    [ValidatePattern('^\d{4}$')]
    [string]$Year,

    # Single digit, matching what the prompt expects (it types "1", the name gets "01").
    [ValidatePattern('^\d$')]
    [string]$UniqueId,

    # Skip the "Is <name> correct? [Y/N]" confirmation. Required for unattended runs, since
    # that prompt is otherwise the one thing that always needs a human.
    [switch]$Force,

    # Stage the rename but don't reboot - lets the caller control when the machine drops,
    # which matters when someone's actively using it or you're driving it over SSH.
    [switch]$NoReboot
)

if ($Company -eq 'MIT') {
    $property = "Loan"
} elseif ($Property) {
    $property = $Property
    Write-Host "Property/extension: $property (from -Property)"
} else {
    $property = Read-Host "Property or Phone Extension Number? [4 digit]"
}

# Auto-detect desktop vs. laptop for every company, using the same battery+chassis signals
# validated in research/Test-MachineDetection.ps1 (100% match against known machine types
# across the field data collected so far). Falls back to the manual prompt for the same
# ambiguous cases that script flags for review (e.g. a UPS-backed desktop reporting a battery).
$LaptopChassisCodes = 8, 9, 10, 14, 30, 31, 32
$DesktopChassisCodes = 3, 4, 5, 6, 7, 13, 15, 16

if ($MachineType) {
    $machinetype = $MachineType
    Write-Host "Machine type: $machinetype (from -MachineType, detection skipped)"
} else {
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

# Year sources, highest priority first:
#   1. -Year.
#   2. The year digit already encoded in this machine's *current* Merion-format name. On a
#      reassignment (machine keeps its name and gets handed to a new user) this beats everything
#      below: it's a year a human already established and confirmed for this exact unit. It also
#      sidesteps a real failure mode of the CPU/OS detection - an in-place Windows upgrade or a
#      reimage rewrites OS InstallDate to *today*, dragging the detected year forward by however
#      long the machine has actually been in service, which silently lands inside the trusted
#      1-3 gap band and produces a wrong year with no warning.
#   3. CPU-generation vs. OS-install-date detection (rule documented below).
#   4. Manual prompt.
function Get-YearFromExistingName {
    param([string]$Name)
    $m = [regex]::Match($Name, '^(?:MRM|MRQ|MRP)\d{4}-(?:DT|LT)(\d)0\d+$')
    if (-not $m.Success) { return $null }
    # The name only carries the year's last digit, so resolve it to the most recent year
    # ending in that digit that isn't in the future.
    $digit = [int]$m.Groups[1].Value
    $thisYear = (Get-Date).Year
    $resolved = ($thisYear - ($thisYear % 10)) + $digit
    if ($resolved -gt $thisYear) { $resolved -= 10 }
    return $resolved
}

$yearpurchased = $null
if ($Year) {
    $yearpurchased = $Year
    Write-Host "Purchase year: $yearpurchased (from -Year)"
} else {
    $existingYear = Get-YearFromExistingName -Name $env:COMPUTERNAME
    if ($existingYear) {
        $yearpurchased = "$existingYear"
        Write-Host "Purchase year: $yearpurchased (carried over from this machine's current name '$env:COMPUTERNAME', which already encodes a confirmed year - CPU/OS detection skipped)"
    }
}

if (-not $yearpurchased) {
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
    } elseif ($Force) {
        throw "Could not determine a purchase year automatically, and -Force was specified so there's no prompt to fall back to. Re-run with an explicit -Year."
    } else {
        $yearpurchased = Read-Host "Year Purchased? [e.g. 2024/2025/2026]"
    }
}

$yearsingle = $yearpurchased.Substring($yearpurchased.Length - 1)

if ($UniqueId) {
    $individual = $UniqueId
    Write-Host "Unique ID: $individual (from -UniqueId)"
} else {
    $individual = Read-Host "Unique ID 01,02,03? [1/2/3]"
}

$NewPCName = "$Company$property-$machinetype$yearsingle" + "0$individual"

Write-Host $NewPCName

if ($Force) {
    Write-Host "-Force specified - skipping the confirmation prompt."
    $namecheck = 'Y'
} else {
    $namecheck = (Read-Host "Is `"$NewPCName`" correct? [Y/N]").ToUpper()
}

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

    # -Force on Rename-Computer suppresses its own confirmation, which otherwise has nothing to
    # read from in a SYSTEM/remote session. -ErrorAction Stop so a failed rename can't fall
    # through into a pointless reboot.
    Rename-Computer -NewName $NewPCName -Force -ErrorAction Stop

    if ($NoReboot) {
        Write-Host "Rename staged - '$NewPCName' takes effect on the next reboot. -NoReboot specified, so this script is not restarting the machine."
    } else {
        Restart-Computer
    }
} else {
    Write-Warning "Name not changed"
}
