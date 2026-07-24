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
<#
.NOTES
	Author	: Gemini
	Version : 1.0
	Description:
		This script disables the "News and Interests" feature on the Windows 10 taskbar
		by modifying specific registry keys. This will hide the News and Interests icon
		and prevent the panel from appearing.
	Compatibility:
		Designed specifically for Windows 10 (all editions).
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Disabling Windows 10 News and Interests..."
Write-Host "======================================="

# --- System-wide policy to disable News and Interests ---
# This key is for controlling the feature via Group Policy,
# but can be set directly in the registry for a system-wide effect.
$policyRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
$policyValueName = "EnableFeeds"
$policyValueData = 0 # 0 to disable, 1 to enable

Write-Host "Checking for and creating registry key for system policy: $policyRegPath"

# Check if the policy registry key exists, if not, create it
If (!(Test-Path $policyRegPath)) {
    try {
        New-Item -Path $policyRegPath -Force | Out-Null
        Write-Host "Registry key '$policyRegPath' created successfully."
    } catch {
        Write-Error "Failed to create registry key '$policyRegPath'. Error: $($_.Exception.Message)"
        Write-Host "Script cannot continue without required registry key for system policy."
        exit 1
    }
}

Write-Host "Setting system policy value to disable News and Interests..."
# Set the EnableFeeds DWORD value to 0 to disable News and Interests system-wide
try {
    Set-ItemProperty -Path $policyRegPath -Name $policyValueName -Type DWord -Value $policyValueData -Force -ErrorAction Stop
    Write-Host "System policy registry value '$policyValueName' set to '$policyValueData' successfully."
} catch {
    Write-Error "Failed to set system policy registry value '$policyValueName'. Error: $($_.Exception.Message)"
    Write-Host "News and Interests system policy may not be disabled."
}


# --- User-specific setting to hide the taskbar icon ---
# This typically controls the visibility of the News and Interests icon on the taskbar
$userRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
$userValueName = "ShellFeedsTaskbarViewMode"
$userValueData = 2 # 0 = Show icon and text, 1 = Show icon only, 2 = Hide icon

Write-Host "Checking for and creating registry key for user setting: $userRegPath"

# Check if the user registry key exists, if not, create it
If (!(Test-Path $userRegPath)) {
    try {
        New-Item -Path $userRegPath -Force | Out-Null
        Write-Host "Registry key '$userRegPath' created successfully."
    } catch {
        Write-Warning "Failed to create user registry key '$userRegPath'. Error: $($_.Exception.Message)"
        Write-Host "User-specific icon hiding may not be fully effective."
    }
}

Write-Host "Setting user-specific taskbar icon visibility..."
# Set the ShellFeedsTaskbarViewMode DWORD value to 2 to hide the icon
try {
    Set-ItemProperty -Path $userRegPath -Name $userValueName -Type DWord -Value $userValueData -Force -ErrorAction Stop
    Write-Host "User-specific registry value '$userValueName' set to '$userValueData' successfully."
} catch {
    Write-Error "Failed to set user-specific registry value '$userValueName'. Error: $($_.Exception.Message)"
    Write-Host "News and Interests taskbar icon may not be hidden."
}

Write-Host "======================================="
Write-Host "News and Interests feature is now disabled on Windows 10."
Write-Host "You may need to restart Explorer (or reboot) for changes to take full effect."
Write-Host "======================================="
