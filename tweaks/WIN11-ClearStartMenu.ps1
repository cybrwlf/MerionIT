<#
.NOTES
	Author	:	Original by Chris Titus @christitustech, Modified by Merion IT Admin
	Version :	Beta
	Target OS: Windows 11 (latest version)

	This script attempts to clear some common pinned items and recommended content from the
	Windows 11 Start Menu by modifying relevant registry keys.
	Note: Windows 11 Start Menu customization is more complex and dynamic than Windows 10.
	Full removal of all pinned/recommended items may not be achievable purely via script
	due to its integration with user activity and cloud features.
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Optimizing Start Menu for Windows 11..."
Write-Host "======================================="

# --- Clear Pinned Items (User Specific) ---
# This often clears user-pinned items. Default pins might reappear.
Write-Host "Attempting to clear user-pinned Start Menu items..."
$pinnedTilesPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartMenu\Tiles\TaskbarWin32"
If (Test-Path $pinnedTilesPath) {
    Get-ItemProperty -Path $pinnedTilesPath | ForEach-Object {
        $_.PSObject.Properties | Where-Object { $_.Name -like "Item*" } | ForEach-Object {
            Remove-ItemProperty -Path $pinnedTilesPath -Name $_.Name -ErrorAction SilentlyContinue
        }
    }
    Write-Host "User-pinned items attempted to be cleared."
} else {
    Write-Host "Pinned items registry path not found for current user."
}

# Clear Recommended Section History (User Specific)
Write-Host "Clearing Recommended section history..."
$recommendedPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Recommended"
If (Test-Path $recommendedPath) {
    Remove-Item -Path $recommendedPath -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $recommendedPath -Force | Out-Null
    Write-Host "Recommended section history cleared."
} else {
    Write-Host "Recommended section registry path not found."
}

# --- Disable Recommended Section (User/System-wide via Policy) ---
# This tries to disable the "Recommended" section entirely.
Write-Host "Attempting to disable 'Recommended' section in Start Menu..."
$policyPathCU = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
$policyPathLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"

If (!(Test-Path $policyPathCU)) { New-Item -Path $policyPathCU -Force | Out-Null }
Set-ItemProperty -Path $policyPathCU -Name "HideRecentlyAddedApps" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue # Hide "Recently added apps"
Set-ItemProperty -Path $policyPathCU -Name "HideAppList" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue # Hide "All apps" list

If (!(Test-Path $policyPathLM)) { New-Item -Path $policyPathLM -Force | Out-Null }
# Hide frequently used apps
Set-ItemProperty -Path $policyPathLM -Name "HideFrequentlyUsedApps" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
# Disable content from Microsoft
Set-ItemProperty -Path $policyPathLM -Name "DisableContentFromMicrosoft" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
# Disable recommendations
Set-ItemProperty -Path $policyPathLM -Name "DisableRecommendedSection" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
Write-Host "'Recommended' section and related features policies set."


# --- Registry keys from original script that are relevant to explorer UI and broadly compatible ---
Write-Host "Applying common Explorer UI tweaks..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCortanaButton" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneExpandToCurrentFolder" -Type DWord -Value 1 -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "EnableDynamicContentInWSB" -Type DWord -Value 0 -ErrorAction SilentlyContinue

# --- Explorer Restart ---
Write-Host "Restarting Explorer to apply UI changes..."
Stop-Process -name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -s 5 # Wait 5 Seconds

Write-Host "Script execution complete for Windows 11."
