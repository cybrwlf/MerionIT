#Requires -RunAsAdministrator

# Check if an argument is provided
if (-not $args) {
    Write-Host "Please provide local user name, i.e. singleuser.ps1 UserName"
    exit 1
}

# Save the first argument (AdminName) into a variable
$adminname = $args[0]

# Create Local user with AdminName provided and set temp password
$SecurePassword = ConvertTo-SecureString "Welcome1!" -AsPlainText -Force
New-LocalUser -Name $adminname -Password $SecurePassword -AccountNeverExpires

# Add AdminName to Local Admins group
Add-LocalGroupMember -Group "Administrators" -Member $adminname

# Remove Password expiration
$User = Get-CimInstance Win32_UserAccount -Filter "Name = '$adminname'"
$User.PasswordExpires = $false
Set-CimInstance -CimInstance $User

Write-Host "User '$adminname' has been created and added to the Administrators group."
