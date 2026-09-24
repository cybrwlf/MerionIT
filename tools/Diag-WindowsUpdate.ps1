#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Diagnose a Windows Update loop, then reset the update stack.

.DESCRIPTION
    Built for the classic "installs in seconds, demands a reboot, comes back with the same list"
    loop. Run it, reboot, run it again. Each run writes a timestamped log, so comparing run N to
    run N+1 shows what a single reboot cycle actually accomplished - which is the question that
    matters and the one a screenshot of the Settings page cannot answer.

    ORDER MATTERS. Diagnostics are captured BEFORE the reset, because the reset deletes
    SoftwareDistribution and the update history lives inside it. Resetting first destroys the
    evidence. This is why the reset is at the end of the script rather than the start.

    The single most useful section is UPDATE HISTORY. An update that reports ResultCode 2
    (Succeeded) and then reappears in the pending list means it is installing and being re-offered,
    which is a completely different problem from one that reports 4 (Failed).

.PARAMETER NoReset
    Collect diagnostics only. Use this when you want to read the history without clearing it.

.EXAMPLE
    powershell.exe -ExecutionPolicy Unrestricted -File C:\MerionIT\Diag-WindowsUpdate.ps1
#>
param(
    [switch]$NoReset,
    [string]$LogDir = 'C:\MerionIT\logs'
)

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$prior = @(Get-ChildItem $LogDir -Filter 'wu-diag-*.txt' -ErrorAction SilentlyContinue | Sort-Object Name)
$run   = $prior.Count + 1
$log   = Join-Path $LogDir ("wu-diag-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date))

Start-Transcript -Path $log -Force | Out-Null

function Section($t) { Write-Host "`n===== $t =====" -ForegroundColor Cyan }

Write-Host "Windows Update diagnostic - RUN #$run"
Write-Host "Host   : $env:COMPUTERNAME   User: $env:USERNAME"
Write-Host "Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Log    : $log"
if ($prior) {
    Write-Host "Previous runs (compare against these):"
    $prior | ForEach-Object { "   $($_.Name)" }
}

# --------------------------------------------------------------------------- OS
Section "OS / BUILD"
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
"DisplayVersion : $($cv.DisplayVersion)"
"Build          : $($cv.CurrentBuild).$($cv.UBR)"
"LastBoot       : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
"Free space C:  : $([math]::Round((Get-PSDrive C).Free/1GB,1)) GB"

# ------------------------------------------------------------- Pending reboot
# Every flag Windows uses. A reboot that does not clear these is the whole symptom.
Section "PENDING-REBOOT FLAGS"
$flags = [ordered]@{
    'CBS RebootPending'      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    'CBS RebootInProgress'   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'
    'CBS PackagesPending'    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
    'WU RebootRequired'      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    'WU PostRebootReporting' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'
    'Rename pending'         = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
}
foreach ($k in $flags.Keys) { "{0,-24} {1}" -f $k, (Test-Path $flags[$k]) }

$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA SilentlyContinue).PendingFileRenameOperations
"{0,-24} {1}" -f 'PendingFileRenameOps', $(if ($pfro) { "$($pfro.Count) entries" } else { 'none' })
"{0,-24} {1}" -f 'WinSxS\pending.xml', (Test-Path "$env:SystemRoot\WinSxS\pending.xml")

# ----------------------------------------------------------------- Services
Section "SERVICE STATE"
'wuauserv','bits','cryptsvc','msiserver','trustedinstaller','UsoSvc','WaaSMedicSvc' | ForEach-Object {
    $s = Get-Service $_ -EA SilentlyContinue
    if ($s) { "{0,-18} {1,-10} {2}" -f $s.Name, $s.Status, $s.StartType } else { "{0,-18} not present" -f $_ }
}

# ------------------------------------------------------------ UPDATE HISTORY
# The important section. ResultCode: 0 NotStarted, 1 InProgress, 2 Succeeded,
# 3 SucceededWithErrors, 4 Failed, 5 Aborted.
Section "UPDATE HISTORY (most recent 60)"
try {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $total    = $searcher.GetTotalHistoryCount()
    "Total history entries in datastore: $total"
    if ($total -gt 0) {
        $map = @{0='NotStarted';1='InProgress';2='Succeeded';3='SucceededWithErrors';4='FAILED';5='Aborted'}
        $searcher.QueryHistory(0, [Math]::Min($total,60)) |
            Sort-Object Date -Descending |
            ForEach-Object {
                "{0:yyyy-MM-dd HH:mm}  {1,-20} 0x{2:X8}  {3}" -f `
                    $_.Date, $map[[int]$_.ResultCode], $_.HResult, $_.Title
            }
    } else {
        "History is empty. Expected on the run immediately after a reset - it rebuilds as updates install."
    }
} catch { Write-Warning "History query failed: $($_.Exception.Message)" }

# ----------------------------------------------------------- PENDING UPDATES
Section "PENDING UPDATES"
try {
    $res = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
    "Count: $($res.Updates.Count)"
    $res.Updates | ForEach-Object {
        "{0,-10} {1}" -f $(if ($_.IsDownloaded) {'[dl]'} else {'[   ]'}), $_.Title
    }
} catch { Write-Warning "Search failed: $($_.Exception.Message)" }

# -------------------------------------------------------------- EVENT LOG
Section "WINDOWSUPDATECLIENT EVENTS (last 40)"
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'} `
        -MaxEvents 40 -ErrorAction Stop |
        ForEach-Object { "{0:MM-dd HH:mm}  id={1,-5} {2}" -f $_.TimeCreated, $_.Id, ($_.Message -split "`r?`n")[0] }
} catch { "none found" }

Section "SERVICING / CBS ERRORS (last 20)"
try {
    Get-WinEvent -FilterHashtable @{LogName='Setup'; Level=2,3} -MaxEvents 20 -ErrorAction Stop |
        ForEach-Object { "{0:MM-dd HH:mm}  id={1,-5} {2}" -f $_.TimeCreated, $_.Id, ($_.Message -split "`r?`n")[0] }
} catch { "none found" }

# ------------------------------------------------------------------ DRIVERS
# The pending list is almost entirely drivers. Two things produce a driver loop:
# a driver offered for hardware that is not present, and an offered version older than
# what is installed. Both show up here.
Section "PHANTOM / PROBLEM DEVICES"
Get-PnpDevice -EA SilentlyContinue | Where-Object { $_.Status -ne 'OK' } |
    Select-Object Status, Class, FriendlyName | Format-Table -AutoSize | Out-String

Section "INSTALLED DRIVER VERSIONS (Intel / Realtek / HP / Dell)"
Get-CimInstance Win32_PnPSignedDriver -EA SilentlyContinue |
    Where-Object { $_.DeviceName -and $_.Manufacturer -match 'Intel|Realtek|HP|Hewlett|Dell' } |
    Select-Object @{n='Mfr';e={$_.Manufacturer}}, DeviceName, DriverVersion, DriverDate |
    Sort-Object Mfr, DeviceName | Format-Table -AutoSize | Out-String

# ----------------------------------------------------------------- CBS HEALTH
Section "COMPONENT STORE HEALTH (CheckHealth - fast, flag-read only)"
dism.exe /Online /Cleanup-Image /CheckHealth

# --------------------------------------------------------------------- RESET
if ($NoReset) {
    Section "RESET SKIPPED (-NoReset)"
} else {
    Section "RESETTING WINDOWS UPDATE"
    $svc = 'wuauserv','bits','cryptsvc','msiserver','appidsvc'
    foreach ($s in $svc) {
        Stop-Service $s -Force -EA SilentlyContinue
        "stop  {0,-12} {1}" -f $s, (Get-Service $s -EA SilentlyContinue).Status
    }

    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Rename-Item "$env:SystemRoot\SoftwareDistribution" "SoftwareDistribution.bak-$ts" -EA SilentlyContinue
    Rename-Item "$env:SystemRoot\System32\catroot2"    "catroot2.bak-$ts"             -EA SilentlyContinue
    "SoftwareDistribution cleared : $(-not (Test-Path "$env:SystemRoot\SoftwareDistribution"))"
    "catroot2 cleared             : $(-not (Test-Path "$env:SystemRoot\System32\catroot2"))"

    Get-BitsTransfer -AllUsers -EA SilentlyContinue | Remove-BitsTransfer -EA SilentlyContinue

    foreach ($s in $svc) {
        Set-Service $s -StartupType Automatic -EA SilentlyContinue
        Start-Service $s -EA SilentlyContinue
        "start {0,-12} {1}" -f $s, (Get-Service $s -EA SilentlyContinue).Status
    }
    Write-Host "`nappidsvc often refuses to stop or start on demand. That is normal." -ForegroundColor DarkGray
    Write-Host "wuauserv and bits are the two that must read Running." -ForegroundColor DarkGray
}

Section "DONE - RUN #$run"
Write-Host "Log written to: $log"
Write-Host "Now reboot, then run this script again. Send both logs."

Stop-Transcript | Out-Null
