#Requires -RunAsAdministrator
<#
Consolidated replacement for MRMrenamePC.ps1 / MRQrenamePC.ps1 / MRPrenamePC.ps1 / MITrenamePC.ps1.
Behavior per company matches the original individual scripts exactly:
  - MRM: prompts for a 4-digit property/extension code AND desktop-vs-laptop.
  - MRQ / MRP: prompts for a 4-digit phone extension; machine type is always "LT".
  - MIT: property is always "Loan" (annual MIT-event loaner laptops), no property prompt.
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

if ($Company -eq 'MRM') {
    $machinetype = Read-Host "Desktop or Laptop? [DT/LT]"
} else {
    $machinetype = "LT"
}

$yearpurchased = Read-Host "Year Purchased? [e.g. 2024/2025/2026]"
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
