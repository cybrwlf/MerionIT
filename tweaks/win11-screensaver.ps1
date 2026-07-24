# Enable screensaver
Write-Host "Enabling screensaver..."
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value 1

# Set screensaver to Ribbons
Write-Host "Setting screensaver to Ribbons..."
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value "Ribbons.scr"

# Set screensaver wait time to 5 minutes
Write-Host "Setting screensaver wait time to 5 minutes..."
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value 300

# Apply the changes
Write-Host "Applying changes..."
rundll32.exe user32.dll,UpdatePerUserSystemParameters

Write-Host "Screensaver settings updated successfully!"
