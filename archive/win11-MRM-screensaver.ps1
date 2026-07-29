$osName = (Get-ComputerInfo).OsName

if ($osName -match "Windows 11") {
    Write-Host "This is Windows 11."
}
elseif ($osName -match "Windows 10") {
    Write-Host "This is Windows 10."
}
else {
    Write-Host "This is something other than Windows 11 or Windows 10."
}

# Set the screen saver timeout to 3 minutes (180 seconds)
$timeoutSeconds = 180

# Set image for screen saver
$imagePath = "C:\MerionIT\bg\Image.png"

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

# Activate the changes
RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters

