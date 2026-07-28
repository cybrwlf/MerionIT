#Requires -RunAsAdministrator
<#
Turns off "Search highlights" - the small animated Bing-curated icon that appears in the
taskbar search box - via both the machine-wide policy and the per-user preference.

basic10-11stuff.ps1 already sets the HKLM policy below as part of its much larger sweep, but
during a live end-to-end test the value came back unset afterward even though the script itself
reported no errors, and there's no equivalent for the HKCU per-user override anywhere in this
repo. This script sets both explicitly and is safe to run on its own or alongside
basic10-11stuff.ps1 (setting the same HKLM value twice is a no-op).
#>

Write-Host "======================================="
Write-Host "Disabling Search Highlights in the taskbar search box..."
Write-Host "======================================="

$policyRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
if (!(Test-Path $policyRegPath)) {
    New-Item -Path $policyRegPath -Force | Out-Null
}
Set-ItemProperty -Path $policyRegPath -Name "EnableDynamicContentInWSB" -Type DWord -Value 0 -Force
Write-Host "Machine-wide policy (EnableDynamicContentInWSB) set to 0."

$userRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
if (!(Test-Path $userRegPath)) {
    New-Item -Path $userRegPath -Force | Out-Null
}
Set-ItemProperty -Path $userRegPath -Name "IsDynamicSearchBoxEnabled" -Type DWord -Value 0 -Force
Write-Host "Per-user setting (IsDynamicSearchBoxEnabled) set to 0."

Write-Host "======================================="
Write-Host "Search Highlights disabled. May need Explorer restart or a fresh logon to be visible immediately."
Write-Host "======================================="
