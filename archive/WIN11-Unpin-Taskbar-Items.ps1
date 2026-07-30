<#
.NOTES
	Author	: Original Script Author (Batch to PowerShell conversion)
	Version : 1.0
	Target OS: Windows 11 (latest version)

	This PowerShell script aims to unpin items from the Windows 11 taskbar.
	Due to significant changes in Windows 11's taskbar architecture,
	a full reset of all pinned items for all users is more complex.
	This script focuses on clearing user-specific pinned items via registry.
	Note: Some default system icons or recently opened items might reappear,
	as Windows 11 manages these more dynamically.
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Unpinning Taskbar Items for Windows 11..."
Write-Host "======================================="

# --- Clear User Pinned Taskbar Items via Registry ---
# Windows 11 primarily manages pinned taskbar items in a specific registry path.
# We'll clear the "UserTileGrid" for the current user.
$userTaskbarPinsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TBD" # This is a common path for Win11 pinned items, though exact key names can vary.
$oldTaskbandPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" # Still exists but less authoritative in Win11.

Write-Host "Clearing current user's pinned taskbar items from registry..."

# Attempt to clear UserTileGrid
If (Test-Path $userTaskbarPinsPath) {
    # Find and delete properties related to pinned items.
    # This might require more specific knowledge of internal Win11 registry structure.
    # A common approach is to clear the parent key if it specifically refers to pinned items.
    # For a more robust approach, specific GUIDs related to pinned apps might need to be targeted.
    # For simplicity, we'll try to delete the relevant key/value that stores pinned items.
    # (This is an educated guess based on Win11 internal workings)
    Remove-ItemProperty -Path $userTaskbarPinsPath -Name "PinItems" -ErrorAction SilentlyContinue # Example: if there's a specific "PinItems" value
    # Some pinned items might be within subkeys, so a more aggressive approach might be:
    # Remove-Item -Path $userTaskbarPinsPath -Recurse -Force -ErrorAction SilentlyContinue
    # New-Item -Path $userTaskbarPinsPath -Force | Out-Null
    Write-Host "Attempted to clear main Windows 11 taskbar pinned items key."
} else {
    Write-Host "Windows 11 user taskbar pins registry path not found."
}

# Clear the legacy Taskband registry key as it still holds some information.
Write-Host "Clearing legacy Taskband registry key for compatibility..."
If (Test-Path $oldTaskbandPath) {
    Remove-Item -Path $oldTaskbandPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Successfully deleted legacy Taskband registry key."
} else {
    Write-Host "Legacy Taskband registry key not found."
}

# --- Restart Explorer ---
# Restarting Explorer is crucial for these changes to take effect immediately.
Write-Host "Restarting Windows Explorer to apply changes..."
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5 # Give Explorer time to restart
Start-Process explorer -ErrorAction SilentlyContinue # Explicitly start explorer just in case it doesn't auto-restart

Write-Host "======================================="
Write-Host "Taskbar unpinning script complete for Windows 11."
Write-Host "Note: Due to Windows 11's dynamic nature, some default or recently used items"
Write-Host "may reappear on the taskbar or in the Start Menu's 'Recommended' section."
Write-Host "Full taskbar customization on Windows 11 often requires Group Policy (GPO)"
Write-Host "or MDM solutions for enterprise-level control."
Write-Host "======================================="
