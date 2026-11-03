#Requires -RunAsAdministrator
<#
.SYNOPSIS
    End-of-build check. Says PASS / WARN / FAIL for everything setup is supposed to have done, so a
    half-finished build is caught before the laptop leaves the bench. Changes nothing.

.DESCRIPTION
    Written 2026-11-03 after MIP3004-LT601: setup finished without an error, yet Office, BGInfo and
    the Kaseya agent were all missing and two Dell apps had been left behind. Each check below is one
    of the things that was actually wrong on a real build, plus the basics around it.

    FAIL = setup did not do its job, fix it before handing the machine over.
    WARN = worth a look, not a blocker (pending reboot, open reminder lines, odd state).

    Checks: name, setup markers, secrets file gone, Office (en-us only), BGInfo, apps from
    Install-Apps.ps1, Dell (DCU working, Optimizer / SupportAssist gone), Windows Update policy,
    Kaseya agent health, pending reboot, open lines in Manual-Steps-Reminder.txt.

.NOTES
    Write-Output only, needs no user and no internet, so it is safe through Kaseya as SYSTEM.
    It never runs dcu-cli: DCU is judged by dcu-cli.exe being present and its service running.
    Exit code: 0 = no FAIL, 2 = at least one FAIL.
    Ends with: RESULT|<host>|pass=N|warn=N|fail=N|failed=<names>|v=<version>
#>

$ScriptVersion = '2026-11-03.1'
function Say($m) { Write-Output $m }

$MerionITRoot = 'C:\MerionIT'
$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Name, [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status, [string]$Detail) {
    $results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
    Say ("  {0,-4} {1,-14} {2}" -f $Status, $Name, $Detail)
}

$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = @(Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue | Where-Object DisplayName)
function Test-Installed([string]$Pattern) { [bool]($installed | Where-Object { $_.DisplayName -match $Pattern }) }
$scoopApps = 'C:\ProgramData\scoop\apps'
function Test-Scoop([string]$App) { Test-Path (Join-Path $scoopApps "$App\current") }

Say "=========================================================="
Say " Merion build check  [READ ONLY - no changes]"
Say "=========================================================="
Say "Host    : $env:COMPUTERNAME"
$cs = Get-CimInstance Win32_ComputerSystem
Say "Vendor  : $($cs.Manufacturer) / $($cs.Model)"
Say "Script  : v$ScriptVersion"
Say ""

# --- Name and setup markers ---
if ($env:COMPUTERNAME -match '^(MRM|MRQ|MRP|MIP|MIT)') {
    Add-Result 'name' 'PASS' $env:COMPUTERNAME
} else {
    Add-Result 'name' 'FAIL' "$env:COMPUTERNAME is not an MRM/MRQ/MRP/MIP/MIT name - rename did not run or was not rebooted"
}
if (Test-Path "$MerionITRoot\.setup-complete") {
    Add-Result 'setup-complete' 'PASS' "marker present ($((Get-Content "$MerionITRoot\.setup-complete" -Raw).Trim()))"
} else {
    Add-Result 'setup-complete' 'FAIL' "$MerionITRoot\.setup-complete missing - Step1 did not finish"
}
if (Test-Path "$MerionITRoot\.agent-repair-pending") {
    Add-Result 'agent-marker' 'FAIL' "$MerionITRoot\.agent-repair-pending still there - the post-rename agent repair has not succeeded yet"
}
$secrets = @(Get-ChildItem $MerionITRoot -Filter 'secrets*.psd1' -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'secrets.template.psd1' })
if ($secrets) {
    Add-Result 'secrets' 'FAIL' "credentials file left on the machine: $(($secrets.FullName) -join ', ')"
} else {
    Add-Result 'secrets' 'PASS' "no secrets file under $MerionITRoot"
}

# --- Office ---
# Same rule as setup\Fix-OfficeLanguages.ps1: a product listed in Click-to-Run AND Word on disk. An
# empty ClickToRun key by itself is not Office (MIP3004-LT601).
$c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
$officeRoot = if ($c2r.InstallationPath) { $c2r.InstallationPath } else { "$env:ProgramFiles\Microsoft Office" }
$word = Join-Path $officeRoot 'root\Office16\WINWORD.EXE'
if ($c2r.ProductReleaseIds -and (Test-Path $word)) {
    $langs = @($installed | Where-Object { $_.DisplayName -match '^Microsoft 365 - ([a-z]{2}-[a-z]{2})$' } |
        ForEach-Object { $matches[1] } | Select-Object -Unique)
    $extra = @($langs | Where-Object { $_ -ne 'en-us' })
    if ($extra) {
        Add-Result 'office' 'FAIL' "extra language packs: $($extra -join ', ') - run setup\Fix-OfficeLanguages.ps1"
    } else {
        Add-Result 'office' 'PASS' "$($c2r.ProductReleaseIds) $($c2r.VersionToReport), en-us only"
    }
} else {
    Add-Result 'office' 'FAIL' "not installed (product: '$($c2r.ProductReleaseIds)', WINWORD.EXE: $(Test-Path $word)) - run setup\Fix-OfficeLanguages.ps1"
}

# --- BGInfo ---
$bginfo = Get-ChildItem 'C:\BGinfo' -Filter 'Bginfo*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$bginfoBat = Test-Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\bginfo.bat"
if ($bginfo -and $bginfoBat) {
    Add-Result 'bginfo' 'PASS' "$($bginfo.Name) $($bginfo.VersionInfo.FileVersion), startup entry present"
} else {
    Add-Result 'bginfo' 'FAIL' "exe: $([bool]$bginfo), startup bat: $bginfoBat - run tweaks\bginfo.ps1"
}

# --- Apps (setup\Install-Apps.ps1 list: winget or Scoop, so either counts) ---
$apps = [ordered]@{
    'Adobe Acrobat Reader' = { Test-Installed '^Adobe Acrobat' }
    'Google Chrome'        = { (Test-Installed '^Google Chrome$') -or (Test-Scoop 'googlechrome') }
    '7-Zip'                = { (Test-Installed '^7-Zip') -or (Test-Scoop '7zip') }
    'Microsoft Teams'      = { [bool](Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction SilentlyContinue) }
    'Advanced IP Scanner'  = { (Test-Scoop 'advanced-ip-scanner') -or (Test-Installed '^Advanced IP Scanner') }
}
$missingApps = @($apps.Keys | Where-Object { -not (& $apps[$_]) })
if ($missingApps) {
    Add-Result 'apps' 'FAIL' "missing: $($missingApps -join ', ') - run setup\Install-Apps.ps1"
} else {
    Add-Result 'apps' 'PASS' "all $($apps.Count) present"
}

# --- Dell ---
$isDell = $cs.Manufacturer -match 'Dell'
$dcuCli = @(foreach ($r in $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
    $p = Join-Path $r 'Dell\CommandUpdate\dcu-cli.exe'; if (Test-Path $p) { $p }
}) | Select-Object -First 1
if ($isDell) {
    $dcuSvc = Get-Service -Name 'DellClientManagementService' -ErrorAction SilentlyContinue
    if ($dcuCli -and $dcuSvc.Status -eq 'Running') {
        Add-Result 'dell-dcu' 'PASS' "dcu-cli present, DellClientManagementService running"
    } else {
        Add-Result 'dell-dcu' 'FAIL' "dcu-cli: $([bool]$dcuCli), service: $(if ($dcuSvc) { $dcuSvc.Status } else { 'missing' }) - run tweaks\vendor-drivers.ps1"
    }
    $bloat = @('Dell Optimizer', 'Dell/Alienware Purchased Apps', 'Dell SupportAssist', 'Dell SupportAssist Remediation',
        'Dell SupportAssist OS Recovery Plugin for Dell Update' | Where-Object { Test-Installed "^$([regex]::Escape($_))$" })
    if (Get-AppxPackage -AllUsers -Name '*SupportAssist*' -ErrorAction SilentlyContinue) { $bloat += 'SupportAssist (Store app)' }
    if ($bloat) {
        Add-Result 'dell-bloat' 'FAIL' "still installed: $($bloat -join ', ') - run tweaks\vendor-drivers.ps1"
    } else {
        Add-Result 'dell-bloat' 'PASS' 'Optimizer, Purchased Apps and SupportAssist gone (Trusted Device kept on purpose)'
    }
}

# --- Windows Update policy (same rules as tools\Repair-MerionWindowsUpdate.ps1) ---
$wu = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
$au = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
# Kaseya patch management owns Windows Update on these and writes the AU values itself (MIP3004-LT601,
# 2026-11-03), so they are not a problem there. Keep in step with $KaseyaPatchedPrefixes in that script.
$KaseyaPatchedPrefixes = @('MIP')
$kaseyaPatched = [bool]($KaseyaPatchedPrefixes | Where-Object { $env:COMPUTERNAME -like "$_*" })
$wuProblems = @()
if (-not $kaseyaPatched) {
    if ($au.NoAutoUpdate -eq 1 -or $au.AUOptions -eq 1) { $wuProblems += "automatic updates disabled (NoAutoUpdate=$($au.NoAutoUpdate), AUOptions=$($au.AUOptions))" }
    if ($au.NoAutoRebootWithLoggedOnUsers -eq 1) { $wuProblems += 'NoAutoRebootWithLoggedOnUsers=1 (managed-by-your-organization banner)' }
}
if ($isDell -and $dcuCli -and $wu.ExcludeWUDriversInQualityUpdate -ne 1) { $wuProblems += 'Dell with DCU but Windows Update still offers drivers' }
if (-not $isDell -and $wu.ExcludeWUDriversInQualityUpdate -eq 1) { $wuProblems += 'non-Dell but Windows Update driver offers are blocked' }
if ($wuProblems) {
    Add-Result 'windows-update' 'FAIL' "$($wuProblems -join '; ') - run tools\Repair-MerionWindowsUpdate.ps1"
} else {
    Add-Result 'windows-update' 'PASS' "policy matches standard (driver exclusion=$([int]$wu.ExcludeWUDriversInQualityUpdate)$(if ($kaseyaPatched) { ', AU values left to Kaseya patch management' }))"
}

# --- Kaseya agent (same three signals as setup\Agent-Install.ps1) ---
$agentServices = @(Get-Service | Where-Object { $_.DisplayName -like '*Kaseya Agent*' })
if (-not $agentServices) {
    Add-Result 'kaseya' 'FAIL' 'no Kaseya Agent service - run setup\Agent-Install.ps1'
} else {
    $agentProblems = @($agentServices | Where-Object Status -ne 'Running' | ForEach-Object { "'$($_.DisplayName)' is $($_.Status)" })
    if (-not (Get-CimInstance Win32_Process -Filter "Name = 'AgentMon.exe'" -ErrorAction SilentlyContinue)) { $agentProblems += 'AgentMon.exe not running' }
    $connected = $false
    for ($i = 0; $i -lt 12 -and -not $connected; $i++) {
        $agentPids = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -like '*\Kaseya\*' } | ForEach-Object { $_.ProcessId })
        $connected = [bool](Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
            Where-Object { $agentPids -contains $_.OwningProcess })
        if (-not $connected) { Start-Sleep -Seconds 5 }
    }
    if (-not $connected) { $agentProblems += 'no connection to the Kaseya server after 60 s' }
    if ($agentProblems) {
        Add-Result 'kaseya' 'FAIL' "$($agentProblems -join '; ') - run setup\Agent-Install.ps1 -Repair"
    } else {
        Add-Result 'kaseya' 'PASS' 'services running, AgentMon running, connected'
    }
}

# --- Pending reboot and open reminder lines (WARN only) ---
$rebootPending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($rebootPending) { Add-Result 'reboot' 'WARN' 'a reboot is pending' }
$reminder = "$MerionITRoot\setup\Manual-Steps-Reminder.txt"
$open = @(Get-Content $reminder -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*\[ \]' })
if ($open) {
    Add-Result 'reminders' 'WARN' "$($open.Count) open line(s) in Manual-Steps-Reminder.txt:"
    $open | ForEach-Object { Say "         $($_.Trim())" }
}

$pass = @($results | Where-Object Status -eq 'PASS').Count
$warn = @($results | Where-Object Status -eq 'WARN').Count
$failed = @($results | Where-Object Status -eq 'FAIL' | ForEach-Object Name)
Say ""
Say $(if ($failed) { "BUILD NOT DONE: $($failed.Count) FAIL(s)." } else { "BUILD OK (no FAIL)." })
Say "RESULT|$env:COMPUTERNAME|pass=$pass|warn=$warn|fail=$($failed.Count)|failed=$($failed -join ',')|v=$ScriptVersion"
if ($failed) { exit 2 } else { exit 0 }
