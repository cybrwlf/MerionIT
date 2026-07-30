<#
.NOTES
	Author	: Original Script Author (Batch to PowerShell conversion)
	Version : 1.0
	Target OS: Windows 10 (latest version)

	This PowerShell script aims to unpin all items from the taskbar for the current user
	on Windows 10. It works by deleting pinned shortcuts and associated registry keys,
	followed by an Explorer restart to apply changes.
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Unpinning Taskbar Items for Windows 10..."
Write-Host "======================================="

# --- Clear Pinned Taskbar Shortcuts ---
# This path contains the actual shortcut files for pinned taskbar items on Windows 10.
$taskbarPinsPath = "$env:AppData\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
Write-Host "Deleting pinned taskbar shortcuts from: $taskbarPinsPath"
If (Test-Path $taskbarPinsPath) {
    Remove-Item -Path "$taskbarPinsPath\*" -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "Successfully deleted taskbar shortcuts."
} else {
    Write-Host "Taskbar pinned shortcuts path not found, or already clear."
}

# --- Clear Taskband Registry Key ---
# This registry key stores information about pinned applications on the taskbar.
$taskbandRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
Write-Host "Deleting Taskband registry key: $taskbandRegPath"
If (Test-Path $taskbandRegPath) {
    Remove-Item -Path $taskbandRegPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Successfully deleted Taskband registry key."
} else {
    Write-Host "Taskband registry key not found, or already clear."
}

# --- Restart Explorer ---
# Restarting Explorer is crucial for these changes to take effect immediately.
Write-Host "Restarting Windows Explorer to apply changes..."
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5 # Give Explorer time to restart
Start-Process explorer -ErrorAction SilentlyContinue # Explicitly start explorer just in case it doesn't auto-restart

Write-Host "======================================="
Write-Host "Taskbar unpinning script complete for Windows 10."
Write-Host "Please note: Some system-default icons may re-appear on next login or system restart."
Write-Host "======================================="
