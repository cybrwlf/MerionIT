#Requires -RunAsAdministrator
<#
Separate, standalone script - NOT related to SingleUser.ps1. Used once a year to set up a handful
of loaner laptops for the annual "MIT" event. Machines get wiped after the event, so this account
is intentionally lower-security/short-lived.
#>
param(
    [string]$SecretsPath = "C:\MerionIT\secrets.psd1"
)

if (-not (Test-Path $SecretsPath)) {
    throw "secrets.psd1 not found at $SecretsPath - copy it from the USB stick before running this script."
}
$secrets = Import-PowerShellDataFile -Path $SecretsPath
$adminname = "MITLoaner"

if (Get-LocalUser -Name $adminname -ErrorAction SilentlyContinue) {
    Write-Host "User '$adminname' already exists. Skipping creation..." -ForegroundColor Yellow
} else {
    $SecurePassword = ConvertTo-SecureString $secrets.MitLoanerPassword -AsPlainText -Force
    New-LocalUser -Name $adminname -Password $SecurePassword -AccountNeverExpires
    Add-LocalGroupMember -Group "Administrators" -Member $adminname
    Set-LocalUser -Name $adminname -PasswordNeverExpires $true
    Write-Host "User '$adminname' has been created and added to the Administrators group."
}
