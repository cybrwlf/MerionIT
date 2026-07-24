# Set the screen saver timeout to 3 minutes (180 seconds)
$timeoutSeconds = 180

# Set image for screen saver
$imagePath = "C:\MerionIT\bg\Image.png"

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

# Activate the changes
RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters



