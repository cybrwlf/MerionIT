# Get the computer's and os name
$computerName = [System.Net.Dns]::GetHostName()
$osName = (Get-ComputerInfo).OsName



# Extract the 4th through 7th characters
$PropID = $computerName.Substring(3, 4)

# Set the screen saver timeout to 3 minutes (180 seconds)
$timeoutSeconds = 180



#Grab image and place in BGINFO folder
# Define the URL of the image
$url = "https://my.merionresidential.com/bginfo/202309$PropID.png"
if (!(Test-Path $url)) {
    # URL doesn't exist, so change it to a new URL
    $url = "https://my.merionresidential.com/bginfo/202309%20ALL%20PROPERTIES-rainbow.png"
}

# Define the path where you want to save the image
$imagePath = "C:\MerionIT\bginfo\MerionLogo.png"

# Create the destination directory if it doesn't exist
if (!(Test-Path -Path "C:\MerionIT\bginfo" -PathType Container)) {
    New-Item -Path "C:\MerionIT\bginfo" -ItemType Directory
	Write-Host "MerionIT\bginfo Folder Created "
}


# Display Variables
Write-Host "----- Display Variables -----"
Write-Host "Computer Name: $computerName"
Write-Host "OS Name: $osName"
Write-Host "PropID: $PropID"
Write-Host "Timoue in Seconds: $timeoutSeconds"
Write-Host "URL to retrieve: $url"
Write-Host "Location for Image: $imagePath"


sleep 10

Write-Host "----- start -----"
# Download the image from the URL and save it to the destination path
Invoke-WebRequest -Uri $url -OutFile $imagePath



if ($osName -match "Windows 11") {
    Write-Host "This is Windows 11."
	
if (!(Test-Path "HKCU:\Control Panel\Desktop\ScreenSaveActive")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value 1
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value 1
}

if (!(Test-Path "HKCU:\Control Panel\Desktop\SCRNSAVE.EXE")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value "C:\Windows\System32\PhotoScreensaver.scr" -PropertyType String -Force
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value "C:\Windows\System32\PhotoScreensaver.scr" -PropertyType String -Force
}

if (!(Test-Path "HKCU:\Control Panel\Desktop\ScreenSaveTimeOut")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value $timeoutSeconds
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value $timeoutSeconds
}

if (!(Test-Path "HKCU:\Control Panel\Desktop\ScreenSaveTimeOut")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UsePhotos" -Value 1
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UsePhotos" -Value 1
}

if (!(Test-Path "HKCU:\Control Panel\Desktop\ScreenSaveTimeOut")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Photofile" -Value $imagePath
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Photofile" -Value $imagePath
}


}
elseif ($osName -match "Windows 10") {
    Write-Host "This is Windows 10."

if (!(Test-Path "HKCU:\Control Panel\Desktop\ScreenSaveActive")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value 1
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value 1
}
	
# Check if the registry items exist, and if not, create them
if (!(Test-Path "HKCU:\Control Panel\Desktop\ScreenSaveTimeOut")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value $timeoutSeconds -PropertyType DWORD -Force
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value $timeoutSeconds -PropertyType DWORD -Force
}

if (!(Test-Path "HKCU:\Control Panel\Desktop\SCRNSAVE.EXE")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value "C:\Windows\System32\PhotoScreensaver.scr" -PropertyType String -Force
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value "C:\Windows\System32\PhotoScreensaver.scr" -PropertyType String -Force
}

if (!(Test-Path "HKCU:\Control Panel\Desktop\UsePhotos")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UsePhotos" -Value 1 -PropertyType DWORD -Force
} else {
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UsePhotos" -Value 1 -PropertyType DWORD -Force
}

if (!(Test-Path "HKCU:\Control Panel\Desktop\Photofile")) {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Photofile" -Value $imagePath -PropertyType String -Force
} else {
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Photofile" -Value $imagePath -PropertyType String -Force
}

}
else {
    Write-Host "This is something other than Windows 11 or Windows 10."
}


# Activate the changes
RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters

