#Requires -RunAsAdministrator
<#
Removes a departed user's Windows profile (and, by default, their local account) from a machine
being reassigned to someone else.

Rewritten 2026-09-18. The previous version had three real faults, all of which could bite on a
live machine:
  - It guarded with Get-WmiObject inside a try/catch, but that cmdlet returns $null for a
    missing user rather than throwing, so the "user not found" check never fired and the script
    happily proceeded to wipe C:\Users\<whatever you typed>.
  - It renamed AppData, recursively deleted the profile contents by hand, then called
    Remove-Item on the folder *without* -Recurse, which fails on anything left behind.
  - It never touched the ProfileList registry entry, so Windows still believed the profile
    existed and would rebuild it as <user>.000 on next logon.

This version hands the whole job to Win32_UserProfile instead, which is the supported path and
removes the folder and the registry entry together.

Because this deletes user data, it defaults to asking. Run with -WhatIf first to see exactly
what would go, and -Confirm:$false only once you're happy with that list.

  .\RemoveUserProfile.ps1 -UserName jdoe -WhatIf
  .\RemoveUserProfile.ps1 -UserName jdoe
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserName,

    # Remove the profile but leave the local account itself alone.
    [switch]$KeepAccount
)

$account = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

# Match the profile by SID where we can (authoritative), falling back to the folder name for a
# profile whose account has already been deleted.
$userProfile = if ($account) {
    Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($account.SID.Value)'" -ErrorAction SilentlyContinue
} else {
    Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPath -and (Split-Path $_.LocalPath -Leaf) -ieq $UserName }
}

if (-not $account -and -not $userProfile) {
    Write-Warning "No local account and no profile found for '$UserName' - nothing to do."
    return
}

if ($userProfile) {
    if ($userProfile.Special) {
        throw "'$($userProfile.LocalPath)' is a system profile - refusing to touch it."
    }
    if ($userProfile.Loaded) {
        throw "The profile at '$($userProfile.LocalPath)' is currently loaded ('$UserName' is still signed in). Sign them out or reboot, then re-run."
    }

    $sizeGB = [math]::Round(
        ((Get-ChildItem -LiteralPath $userProfile.LocalPath -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum / 1GB), 2)
    Write-Host "Profile : $($userProfile.LocalPath)  (~$sizeGB GB, last used $($userProfile.LastUseTime))"
}
if ($account) {
    Write-Host "Account : $UserName  (SID $($account.SID.Value))"
}

if ($userProfile) {
    if ($PSCmdlet.ShouldProcess($userProfile.LocalPath, "Delete Windows user profile (folder and ProfileList registry entry)")) {
        Remove-CimInstance -InputObject $userProfile -ErrorAction Stop
        Write-Host "Removed profile $($userProfile.LocalPath)."
    }
}

if ($account -and -not $KeepAccount) {
    if ($PSCmdlet.ShouldProcess($UserName, "Delete local user account")) {
        Remove-LocalUser -Name $UserName -ErrorAction Stop
        Write-Host "Removed local account $UserName."
    }
} elseif ($account) {
    Write-Host "-KeepAccount specified - local account '$UserName' left in place."
}
