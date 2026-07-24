param (
    [Parameter(Mandatory = $true)]
    [string]$UserName
)

# Check if the UserName argument is empty
if (-not $UserName) {
    Write-Host "Usage: .\RemoveUserProfile.ps1 -UserName <UserName>"
    Write-Host "Please provide the username of the user you want to remove."
    return
}

# Check if the user exists
try {
    $UserAccount = Get-WmiObject Win32_UserAccount -Filter "Name='$UserName'"
}
catch {
    Write-Host "Error: User '$UserName' not found."
    return
}

# Define the user profile folder path
$UserProfile = "C:\Users\$UserName"

# Rename the AppData folder to "AppData_old" and remove hidden attribute
$AppDataFolderPath = Join-Path -Path $UserProfile -ChildPath "AppData"
$AppDataOldFolderPath = Join-Path -Path $UserProfile -ChildPath "AppData_old"

if ((Test-Path $AppDataFolderPath) -and !(Test-Path $AppDataOldFolderPath)) {
    Rename-Item -Path $AppDataFolderPath -NewName "AppData_old" -Force
}

$attributes = [System.IO.FileAttributes]::Hidden
if ((Get-Item $AppDataOldFolderPath -ErrorAction SilentlyContinue) -ne $null) {
    Get-ChildItem -Path $AppDataOldFolderPath -Recurse | ForEach-Object {
        $_.Attributes = $_.Attributes -bxor $attributes
    }
}

# Now, remove all files and subfolders in the user's profile folder
Get-ChildItem -Path $UserProfile -Recurse | Remove-Item -Force -Recurse

# Check if the AppData_old folder is empty
$AppDataOldFolderEmpty = $true
if (Test-Path $AppDataOldFolderPath) {
    if ((Get-ChildItem -Path $AppDataOldFolderPath -Recurse -ErrorAction SilentlyContinue).Count -ne 0) {
        $AppDataOldFolderEmpty = $false
    }
}

# If AppData_old folder is empty, proceed with the user account removal
if ($AppDataOldFolderEmpty) {
    # After removing all files and subfolders, you can delete the user account
    Remove-LocalUser -Name $UserName

    # Finally, remove the user's profile folder
    Remove-Item -Path $UserProfile -Force
}
else {
    Write-Host "AppData_old folder is not empty. Please make sure all AppData content is removed before running the script again to delete the user account."
}
