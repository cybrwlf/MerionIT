#Requires -RunAsAdministrator
<#
Consolidated replacement for DefaultMRMaccounts.ps1 / DefaultMRQaccounts.ps1 / DefaultMRPaccounts.ps1.
Shares one CreateOrUpdateAccount function (adds the account to the Users group for login-screen
visibility, and ensures Administrators membership whenever addToAdministrators is true - whether
the account is being created fresh or already existed). Per-company behavior:
  - MRM: pcsadmin + TempUser (shared property account, not an admin). Scanner-account creation is
    legacy/disabled for new setups (all properties use Scan-to-Email now) - left commented out, do
    not remove.
  - MRQ: pcsadmin + one named user account (prompted), local admin. Changed 2026-07-28 - the
    original DefaultMRQaccounts.ps1 did NOT make this account an admin, but Merion IT now wants
    MRQ named hires to have admin rights on their own machine.
  - MRP: pcsadmin only today - named-user creation intentionally left disabled, matching the original
    DefaultMRPaccounts.ps1 (uncomment when MRP starts needing individual named accounts).
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('MRM', 'MRQ', 'MRP')]
    [string]$Company,

    [string]$SecretsPath = "C:\MerionIT\secrets.psd1"
)

if (-not (Test-Path $SecretsPath)) {
    throw "secrets.psd1 not found at $SecretsPath - copy it from the USB stick before running this script."
}
$secrets = Import-PowerShellDataFile -Path $SecretsPath

function CreateOrUpdateAccount {
    param (
        [string]$username,
        [string]$password,
        [string]$description,
        [bool]$addToAdministrators
    )

    $existingAccount = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    if ($existingAccount) {
        $existingAccount | Set-LocalUser -Password (ConvertTo-SecureString $password -AsPlainText -Force)
        Write-Host "Updated password for $username."
    } else {
        New-LocalUser -Name $username -Password (ConvertTo-SecureString $password -AsPlainText -Force) -Description $description
        Write-Host "Created $username account."
    }

    if ($addToAdministrators) {
        $isAdmin = Get-LocalGroupMember -Group "Administrators" | Where-Object { $_.Name -like "*\$username" }
        if (-not $isAdmin) {
            Add-LocalGroupMember -Group "Administrators" -Member $username
            Write-Host "Added $username to the Administrators local group."
        } else {
            Write-Host "$username is already a member of the Administrators local group. Skipping."
        }
    }

    Set-LocalUser -Name $username -PasswordNeverExpires $true

    $isUsersMember = Get-LocalGroupMember -Group "Users" | Where-Object { $_.Name -like "*\$username" }
    if (-not $isUsersMember) {
        Add-LocalGroupMember -Group "Users" -Member $username
        Write-Host "Added $username to the Users local group for visibility."
    }
}

# pcsadmin - every company
CreateOrUpdateAccount -username "pcsadmin" -password $secrets.PcsAdminPassword -description "PCSAdmin Account" -addToAdministrators $true

switch ($Company) {
    'MRM' {
        $fourdigit = Read-Host "Enter four-digit property code"
        CreateOrUpdateAccount -username "TempUser" -password ($secrets.TempUserPasswordBase + $fourdigit) -description "Temporary User Account" -addToAdministrators $false

        # Legacy: local "scanner" account. All properties now use Scan-to-Email on the MFP, so new
        # setups no longer create this account. Left here for reference only - do not remove, and do
        # not touch existing scanner accounts on machines that already have them.
        # CreateOrUpdateAccount -username "scanner" -password ("Prop" + $fourdigit) -description "Scanner Account" -addToAdministrators $true
    }
    'MRQ' {
        $Uname = Read-Host "Enter Username (i.e. jdoe) - leave blank to skip if the named user account was already created on a prior run"
        if ([string]::IsNullOrWhiteSpace($Uname)) {
            Write-Host "No username entered - skipping named user account creation."
        } else {
            CreateOrUpdateAccount -username $Uname -password $secrets.SingleUserTempPassword -description "MRQ User Account" -addToAdministrators $true
        }
    }
    'MRP' {
        # Named-user creation intentionally disabled for MRP today (pcsadmin only), matching the
        # original DefaultMRPaccounts.ps1. Uncomment when MRP starts needing individual named accounts:
        # $Uname = Read-Host "Enter Username (i.e. jdoe)"
        # CreateOrUpdateAccount -username $Uname -password $secrets.SingleUserTempPassword -description "MRP User Account" -addToAdministrators $false
    }
}

Write-Host "Finished Setup Default $Company Accounts"
