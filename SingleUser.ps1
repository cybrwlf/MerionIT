#Requires -RunAsAdministrator
<#
Canonical "new employee" account script. Creates one named local admin account for an employee
who needs their own desk setup - deliberately safe to leave on disk indefinitely (unlike
DefaultAccounts.ps1/RenamePC.ps1, which get scrubbed once initial setup completes): it prompts
for the password interactively, so it works standalone on an already-set-up machine with no
extra prep needed to add a new hire.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$UserName
)

if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Write-Host "User '$UserName' already exists. Skipping creation..." -ForegroundColor Yellow
} else {
    try {
        $SecurePassword = Read-Host -Prompt "Enter a temporary password for '$UserName'" -AsSecureString
        New-LocalUser -Name $UserName -Password $SecurePassword -AccountNeverExpires -ErrorAction Stop
        Add-LocalGroupMember -Group "Administrators" -Member $UserName -ErrorAction Stop
        Set-LocalUser -Name $UserName -PasswordNeverExpires $true
        Write-Host "Success: User '$UserName' created and added to Administrators." -ForegroundColor Green
    }
    catch {
        Write-Error "An error occurred: $($_.Exception.Message)"
    }
}
