#Requires -RunAsAdministrator
<#
One-off rename of a machine, outside the normal Setup.bat flow.

Wraps setup\RenamePC.ps1 (same naming rules, same prompts) but changes what happens at the end:
RenamePC.ps1 on its own reboots the instant you confirm the name, which is right for Setup.bat and
wrong when you're running this from a USB stick. Here the rename is staged with -NoReboot, you are
told to pull the stick, and the restart only happens when you press a key.

It also removes the RunOnce entry RenamePC.ps1 writes. That entry relaunches Step1 from C:\MerionIT
after the reboot, which is wanted inside Setup.bat and unwanted for a rename-only run.

Parameters are optional and passed straight through to RenamePC.ps1; anything omitted is prompted for.
Setup.bat is not touched and does not call this.
#>
param(
    [ValidateSet('MRM', 'MRQ', 'MRP', 'MIT')]
    [string]$Company,
    [ValidatePattern('^\d{4}$')]
    [string]$Property,
    [ValidateSet('DT', 'LT')]
    [string]$MachineType,
    [ValidatePattern('^\d{4}$')]
    [string]$Year,
    [ValidatePattern('^\d$')]
    [string]$UniqueId
)

$ErrorActionPreference = 'Stop'
$renameScript = Join-Path $PSScriptRoot '..\setup\RenamePC.ps1'
if (-not (Test-Path $renameScript)) {
    Write-Error "Can't find $renameScript. Run this from the MerionIT folder it ships in."
}

if (-not $Company) {
    Write-Host ""
    Write-Host "Select company"
    Write-Host "1  Merion (MRM)"
    Write-Host "2  Merion HQ (MRQ)"
    Write-Host "3  Merion Realty Partners (MRP)"
    Write-Host "4  Loaner (MIT)"
    $Company = switch (Read-Host "Select number corresponding to which company") {
        '1' { 'MRM' } '2' { 'MRQ' } '3' { 'MRP' } '4' { 'MIT' }
        default { Write-Error "Not a valid choice." }
    }
}

$renameArgs = @{ Company = $Company; NoReboot = $true }
foreach ($p in 'Property', 'MachineType', 'Year', 'UniqueId') {
    if ((Get-Variable $p).Value) { $renameArgs[$p] = (Get-Variable $p).Value }
}

$before = $env:COMPUTERNAME
& $renameScript @renameArgs

# RenamePC.ps1 prints "Name not changed" and returns normally when the answer was N, so check
# the thing that matters instead of assuming it worked: did a rename get staged?
$pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
if ($pending -eq $before) {
    Write-Warning "No rename was staged ('$before' is unchanged). Nothing to reboot for."
    return
}

# Drop the Step1 auto-resume; a rename-only run shouldn't launch setup on next login.
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' `
    -Name 'MerionITResume' -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Rename staged: $before -> $pending. It takes effect on restart." -ForegroundColor Green
Write-Host "REMOVE THE USB STICK NOW, before the machine restarts." -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter once the USB is out to restart (Ctrl+C to restart later yourself)"
Restart-Computer
