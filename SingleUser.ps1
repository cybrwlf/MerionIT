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
        Set-LocalUser -Name $UserName -PasswordNeverExpires $true
        Write-Host "Created $UserName account."
    }
    catch {
        Write-Error "An error occurred: $($_.Exception.Message)"
    }
}

# Ensure admin membership either way - covers both a fresh account and one that already existed
# but wasn't (yet) a local admin.
try {
    $isAdmin = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop | Where-Object { $_.Name -like "*\$UserName" }
    if (-not $isAdmin) {
        Add-LocalGroupMember -Group "Administrators" -Member $UserName -ErrorAction Stop
        Write-Host "Added $UserName to the Administrators local group." -ForegroundColor Green
    } else {
        Write-Host "$UserName is already a member of the Administrators local group." -ForegroundColor Green
    }
}
catch {
    Write-Error "Could not confirm/add Administrators membership for $UserName : $($_.Exception.Message)"
}
