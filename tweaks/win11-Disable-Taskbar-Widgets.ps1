<#
.NOTES
	Author	: Gemini
	Version : 1.0
	Description:
		This script disables the Widgets feature on Windows 11 by modifying a specific
		registry key. This will hide the Widgets icon from the taskbar and prevent
		the Widgets panel from appearing.
	Compatibility:
		Designed specifically for Windows 11 (all editions).
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Disabling Windows 11 Taskbar Widgets..."
Write-Host "======================================="

# Define the registry path and value for disabling Widgets
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
$valueName = "AllowNewsAndInterests"
$valueData = 0 # 0 to disable, 1 to enable

Write-Host "Checking for and creating registry key: $regPath"

# Check if the registry key exists, if not, create it
If (!(Test-Path $regPath)) {
    try {
        New-Item -Path $regPath -Force | Out-Null
        Write-Host "Registry key '$regPath' created successfully."
    } catch {
        Write-Error "Failed to create registry key '$regPath'. Error: $($_.Exception.Message)"
        Write-Host "Script cannot continue without required registry key."
        exit 1
    }
}

Write-Host "Setting registry value to disable Widgets..."

# Set the AllowNewsAndInterests DWORD value to 0 to disable Widgets
try {
    Set-ItemProperty -Path $regPath -Name $valueName -Type DWord -Value $valueData -Force -ErrorAction Stop
    Write-Host "Registry value '$valueName' set to '$valueData' successfully."
    Write-Host "Widgets feature is now disabled."
} catch {
    Write-Error "Failed to set registry value '$valueName'. Error: $($_.Exception.Message)"
    Write-Host "Widgets feature may not be disabled."
}

Write-Host "======================================="
Write-Host "Please restart your computer for changes to take full effect."
Write-Host "======================================="
