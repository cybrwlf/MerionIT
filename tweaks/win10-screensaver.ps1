# Enable screensaver
Write-Host "-----Begin Configuring screensaver -----"

# Create registry ItemProperty if it does not exist
$registryPath = "HKCU:\Control Panel\Desktop"
$property = "ScreenSaveActive"
$value = 1
if (!(Test-Path -Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}
if (!(Get-ItemProperty -Path $registryPath -Name $property -ErrorAction SilentlyContinue)) {
    New-ItemProperty -Path $registryPath -Name $property -Value $value -Force | Out-Null
}

$property = "SCRNSAVE.EXE"
$value = "Ribbons.scr"
if (!(Get-ItemProperty -Path $registryPath -Name $property -ErrorAction SilentlyContinue)) {
    New-ItemProperty -Path $registryPath -Name $property -Value $value -Force | Out-Null
}

$property = "ScreenSaveTimeOut"
$value = 300
if (!(Get-ItemProperty -Path $registryPath -Name $property -ErrorAction SilentlyContinue)) {
    New-ItemProperty -Path $registryPath -Name $property -Value $value -Force | Out-Null
}


Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value 1

# Set screensaver to Ribbons
Write-Host "Setting screensaver to Ribbons..."
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value "Ribbons.scr"

# Set screensaver wait time to 5 minutes
Write-Host "Setting screensaver wait time to 5 minutes..."
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value 300 -Type string

Write-Host "-----End Configuring screensaver -----"

