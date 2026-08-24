<#
Diagnostic/audit script - NOT itself wired into RenamePC.ps1 or the setup pipeline, and never will
be run standalone during setup (it audits an EXISTING name, which doesn't exist yet at rename time).

However, as of 2026-08-14 its machine-type detection logic (battery + chassis, below) was ported
into RenamePC.ps1 directly, once the field data logged here showed it matched 100% of known
machine names - see RenamePC.ps1's header for details. Year detection (CPU-generation lookup)
remains audit-only here and is NOT wired in anywhere yet - the gap between CPU launch year and
purchase year isn't a fixed offset, so it's still just building sample size for now.

Two things this does, both read-only except for the logs it appends to:

1. Gathers offline (no-internet) signals - battery presence, chassis type, CPU generation - to see
   which ones reliably predict laptop-vs-desktop and purchase year, so RenamePC.ps1 can eventually
   auto-fill those instead of asking the tech every time.
2. Audits the machine's CURRENT name against those same signals - parses the existing
   Company+Property-TypeYear0Unit name and flags it for review if the detected type/year don't
   line up with what the name claims. Useful for visiting already-completed machines and checking
   whether they were named correctly at setup time, not just for brand-new ones.

Audit-only right now - no interactive prompts. Meant to run from a USB stick alongside this
repo's other files; IntelGenYears.csv (lookup table) and all logs live next to this script via
$PSScriptRoot, so the whole folder is self-contained no matter what drive letter it lands on.
#>
param(
    [string]$LogPath = "$PSScriptRoot\MachineDetection-Log.csv",
    [string]$GenTablePath = "$PSScriptRoot\IntelGenYears.csv",
    [string]$UnmatchedLogPath = "$PSScriptRoot\UnmatchedCPUs.csv"
)

# --- Machine type: battery presence (primary) cross-checked against SMBIOS chassis code ---

$LaptopChassisCodes = 8, 9, 10, 14, 30, 31, 32
$DesktopChassisCodes = 3, 4, 5, 6, 7, 13, 15, 16

$battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
$hasBattery = [bool]$battery

$enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue
$chassisCode = $enclosure.ChassisTypes | Select-Object -First 1
$chassisSaysLaptop = $chassisCode -in $LaptopChassisCodes
$chassisSaysDesktop = $chassisCode -in $DesktopChassisCodes
$chassisGuess = if ($chassisSaysLaptop) { "Laptop" } elseif ($chassisSaysDesktop) { "Desktop" } else { "Other/Unknown" }

$inferredType = if ($hasBattery -or $chassisSaysLaptop) { "LT" } else { "DT" }

$typeReasonDesc = "Battery present: $hasBattery. Chassis type code: $chassisCode ($chassisGuess)."
$typeNotes = @()
if ($hasBattery -ne $chassisSaysLaptop -and -not $chassisSaysDesktop) {
    $typeNotes += "Battery presence and chassis code don't clearly agree - verify manually."
}
if ($hasBattery -and $chassisSaysDesktop) {
    $typeNotes += "Has a battery but chassis code says Desktop - verify manually (could be a UPS-backed desktop reporting a battery)."
}

# --- Other raw diagnostic signals ---

$bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue

$biosYear = if ($bios.ReleaseDate) { $bios.ReleaseDate.Year } else { $null }
$osInstallYear = if ($os.InstallDate) { $os.InstallDate.Year } else { $null }
$cpuName = $cpu.Name

# --- Year: parse CPU name against the generation lookup table ---

$genTable = Import-Csv -Path $GenTablePath

$genMatch = [regex]::Match($cpuName, '(\d+)(?:st|nd|rd|th)\s+Gen')
$ultraMatch = [regex]::Match($cpuName, 'Ultra\s+\d+\s+(\d)\d{2}')
# Fallback for CPU names with no "Nth Gen" text at all (confirmed happens in the field - e.g.
# "Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz" has no generation wording). The generation is still
# encoded in the model number's leading digits (10-14 for 5-digit numbers like 10700/10310U,
# 2-9 for 4-digit numbers like 8665U) - try the two-digit reading first since it's the only one
# that's unambiguous; only fall back to the one-digit reading if that doesn't land in 10-14.
$modelMatch = [regex]::Match($cpuName, 'i[3579]-(\d{4,5})')

$tableKey = $null
if ($genMatch.Success) {
    $tableKey = $genMatch.Groups[1].Value
    $yearSourceDesc = "CPU name matched `"$($genMatch.Value)`""
} elseif ($ultraMatch.Success) {
    $tableKey = "Ultra$($ultraMatch.Groups[1].Value)"
    $yearSourceDesc = "CPU name matched Core Ultra Series $($ultraMatch.Groups[1].Value) (leading SKU digit)"
} elseif ($modelMatch.Success) {
    $digits = $modelMatch.Groups[1].Value
    $twoDigitPrefix = [int]$digits.Substring(0, 2)
    $oneDigitPrefix = [int]$digits.Substring(0, 1)
    if ($twoDigitPrefix -ge 10 -and $twoDigitPrefix -le 14) {
        $tableKey = "$twoDigitPrefix"
        $yearSourceDesc = "No `"Gen`" text in CPU name - derived generation $twoDigitPrefix from model number `"$($modelMatch.Value)`""
    } elseif ($oneDigitPrefix -ge 2 -and $oneDigitPrefix -le 9) {
        $tableKey = "$oneDigitPrefix"
        $yearSourceDesc = "No `"Gen`" text in CPU name - derived generation $oneDigitPrefix from model number `"$($modelMatch.Value)`""
    } else {
        $yearSourceDesc = "CPU model number `"$($modelMatch.Value)`" didn't resolve to a known generation range"
    }
} else {
    $yearSourceDesc = "No known Intel generation pattern found in CPU name"
}

$matchRow = if ($tableKey) { $genTable | Where-Object { $_.Generation -eq $tableKey } | Select-Object -First 1 } else { $null }
$inferredYear = if ($matchRow) { if ($inferredType -eq 'LT') { $matchRow.LaptopYear } else { $matchRow.DesktopYear } } else { $null }
if ($matchRow) { $yearSourceDesc += " -> $($matchRow.Codename) (confidence: $($matchRow.Confidence))" }

if (-not $matchRow) {
    [PSCustomObject]@{
        Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $cs.Name
        CPUName      = $cpuName
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
    } | Export-Csv -Path $UnmatchedLogPath -Append -NoTypeInformation
}

# --- Audit the machine's CURRENT name against the detected signals ---

$KnownMerionCompanies = 'MRM', 'MRQ', 'MRP', 'MIT'

$currentName = $cs.Name
# Company is any 3-letter code, not just the known MerionIT ones - sibling companies (e.g. MIP,
# MRA) use the same Company+Property-TypeYear0Unit format but aren't part of MerionIT itself.
# The structural audit (type/year) should still run for them; only the "is this a MerionIT
# company" check below is informational.
$nameMatch = [regex]::Match($currentName, '^(?<company>[A-Za-z]{3})(?<property>[A-Za-z0-9]+)-(?<type>DT|LT)(?<yeardigit>\d)0(?<unit>\d+)$')
$nameParsed = $nameMatch.Success
$companyCode = if ($nameParsed) { $nameMatch.Groups['company'].Value.ToUpper() } else { $null }
$isKnownCompany = if ($nameParsed) { $companyCode -in $KnownMerionCompanies } else { $null }
$nameType = if ($nameParsed) { $nameMatch.Groups['type'].Value } else { $null }
$nameYearDigit = if ($nameParsed) { $nameMatch.Groups['yeardigit'].Value } else { $null }

$nameTypeMatches = $null
$nameYearMatches = $null
$impliedNameYear = $null
$observedGapYears = $null
$namingAuditNotes = @()

if (-not $nameParsed) {
    $namingAuditNotes += "Computer name '$currentName' doesn't match the expected Company+Property-TypeYear0Unit pattern at all - can't audit."
} else {
    if (-not $isKnownCompany) {
        $namingAuditNotes += "Company code '$companyCode' is not a recognized MerionIT company (MRM/MRQ/MRP/MIT) - likely a sibling company using the same naming format. Type/year audit below still applies; treat this note as informational only."
    }
    $nameTypeMatches = ($nameType -eq $inferredType)
    if (-not $nameTypeMatches) {
        $namingAuditNotes += "Name says type '$nameType' but detected machine type is '$inferredType' (battery=$hasBattery, chassis code=$chassisCode) - review, may be a tech error."
    }
    if ($inferredYear) {
        $inferredYearLastDigit = $inferredYear.Substring($inferredYear.Length - 1)
        $nameYearMatches = ($nameYearDigit -eq $inferredYearLastDigit)
        if (-not $nameYearMatches) {
            $namingAuditNotes += "Name encodes year-digit '$nameYearDigit' but CPU-based year is $inferredYear (last digit '$inferredYearLastDigit') - review, may be a tech error (or the machine was bought a year after this CPU generation launched)."
        }

        # Resolve the name's single year-digit to the nearest real year that's AT OR AFTER the
        # CPU's launch year (a machine can't have been bought before its own CPU existed), then
        # log the gap. This is exploratory - not a trusted correction yet, just building up a
        # bigger sample to eventually see whether a real offset pattern holds.
        $launchYearInt = [int]$inferredYear
        $decadeBase = [math]::Floor($launchYearInt / 10) * 10
        $impliedNameYear = $decadeBase + [int]$nameYearDigit
        while ($impliedNameYear -lt $launchYearInt) { $impliedNameYear += 10 }
        $observedGapYears = $impliedNameYear - $launchYearInt

        # Normal buying lag observed so far tops out around 3 years - anything past that is a
        # different kind of signal (reimage, hardware swap, bad original naming, etc.), not
        # routine lag. Flagged neutrally - this doesn't guess at which cause it is.
        if ($observedGapYears -gt 3) {
            $namingAuditNotes += "Large gap - investigate."
        }
    } else {
        $namingAuditNotes += "Can't check the name's year digit - no CPU-based year was detected for this machine."
    }
}

# --- Console summary ---

Write-Host ""
Write-Host "=== Machine Detection/Audit: $currentName ===" -ForegroundColor Cyan
Write-Host "Manufacturer/Model : $($cs.Manufacturer) / $($cs.Model)"
Write-Host "CPU                : $cpuName"
Write-Host "BIOS Release Date  : $($bios.ReleaseDate)  (year: $biosYear - unreliable if firmware was ever updated)"
Write-Host "OS Install Date    : $($os.InstallDate)  (year: $osInstallYear - only meaningful same-day as a fresh OOBE setup)"
Write-Host ""
Write-Host "--- Detection ---" -ForegroundColor DarkGray
Write-Host "Machine type: $inferredType ($typeReasonDesc)"
if ($typeNotes) { Write-Host "  NOTE: $($typeNotes -join ' | ')" -ForegroundColor Red }
Write-Host "Year source : $yearSourceDesc"
Write-Host "Inferred year: $inferredYear"
if (-not $matchRow) { Write-Host "  Logged to $UnmatchedLogPath for follow-up." -ForegroundColor Red }
Write-Host ""
Write-Host "--- Naming Audit (does the current name match what we detected?) ---" -ForegroundColor DarkGray
if (-not $nameParsed) {
    Write-Host "  $($namingAuditNotes -join "`n  ")" -ForegroundColor Yellow
} else {
    Write-Host "  Name says: company=$companyCode (known MerionIT company: $isKnownCompany), type=$nameType, year-digit=$nameYearDigit"
    Write-Host "  Type match: $nameTypeMatches | Year match: $nameYearMatches"
    if ($null -ne $observedGapYears) {
        Write-Host "  Implied name year: $impliedNameYear | CPU launch year: $inferredYear | Observed gap: $observedGapYears year(s)"
    }
    if ($namingAuditNotes) { Write-Host "  $($namingAuditNotes -join "`n  ")" -ForegroundColor Yellow }
}

# --- Log ---

$result = [PSCustomObject]@{
    Timestamp             = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName          = $currentName
    Manufacturer          = $cs.Manufacturer
    Model                 = $cs.Model
    CPUName               = $cpuName
    HasBattery            = $hasBattery
    ChassisTypeCode       = $chassisCode
    InferredMachineType   = $inferredType
    TypeNotes             = ($typeNotes -join " | ")
    YearSource            = $yearSourceDesc
    InferredYear          = $inferredYear
    NameParsed            = $nameParsed
    ImpliedNameYear       = $impliedNameYear
    ObservedGapYears      = $observedGapYears
    CompanyCode           = $companyCode
    IsKnownMerionCompany  = $isKnownCompany
    NameType              = $nameType
    NameYearDigit         = $nameYearDigit
    NameTypeMatches       = $nameTypeMatches
    NameYearMatches       = $nameYearMatches
    NamingAuditNotes      = ($namingAuditNotes -join " | ")
    BIOSReleaseDate       = $bios.ReleaseDate
    BIOSReleaseYear       = $biosYear
    OSInstallDate         = $os.InstallDate
    OSInstallYear         = $osInstallYear
    BIOSSerialNumber      = $bios.SerialNumber
    BaseboardManufacturer = $board.Manufacturer
    BaseboardProduct      = $board.Product
    BaseboardSerial       = $board.SerialNumber
}

$result | Export-Csv -Path $LogPath -Append -NoTypeInformation

Write-Host ""
Write-Host "Logged to $LogPath" -ForegroundColor Green
