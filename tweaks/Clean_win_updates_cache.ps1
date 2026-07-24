<#
.NOTES
	Author	: Original Script Author
	Version : 1.0
	Description:
		This script stops essential Windows Update-related services,
		clears the Windows Update cache by removing the SoftwareDistribution folder,
		and then restarts and sets the services back to automatic startup.
	Compatibility:
		Fully compatible with both the latest Windows 10 and Windows 11 machines.
		All commands and targeted services are consistent across these operating systems.
	Requires Administrator privileges to run.
#>

function StopAndVerifyService {
    param (
        [string]$ServiceName
    )

    Write-Host "Attempting to stop service: '$ServiceName'..."
    # Stop the service forcefully
    Stop-Service -Name $ServiceName -force -ErrorAction SilentlyContinue

    # Wait for the service to stop (optional, depending on the service's stop time)
    Start-Sleep -Seconds 5

    # Check if the service is stopped
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service.Status -eq 'Stopped') {
        Write-Host "The service '$ServiceName' has been stopped successfully."
    } else {
        Write-Host "Failed to stop the service '$ServiceName'. Current status: $($service.Status)."
    }
}

function StartAndVerifyService {
    param (
        [string]$ServiceName
    )

    Write-Host "Attempting to start service: '$ServiceName'..."
    # Start the service
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue

    # Wait for the service to start (optional, depending on the service's start time)
    Start-Sleep -Seconds 5

    # Check if the service is running
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service.Status -eq 'Running') {
        Write-Host "The service '$ServiceName' has started successfully."
    } else {
        Write-Host "Failed to start the service '$ServiceName'. Current status: $($service.Status)."
    }
}

Write-Host "======================================="
Write-Host "Initiating Windows Update Cache Cleanup..."
Write-Host "======================================="

# Stop necessary services for Windows Update cleanup
StopAndVerifyService -ServiceName "wuauserv"
StopAndVerifyService -ServiceName "bits"
StopAndVerifyService -ServiceName "cryptsvc"

Write-Host "======================================="
Write-Host "Removing C:\Windows\SoftwareDistribution folder (Windows Update cache)..."
# Remove the SoftwareDistribution folder
Remove-Item -Path "C:\Windows\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue
if (!(Test-Path "C:\Windows\SoftwareDistribution")) {
    Write-Host "Successfully removed C:\Windows\SoftwareDistribution."
} else {
    Write-Host "Failed to remove C:\Windows\SoftwareDistribution. It may be in use."
}
Write-Host "======================================="

Write-Host "Restarting services and setting startup type to Automatic..."
# Start services and set their startup type back to Automatic
StartAndVerifyService -ServiceName "wuauserv"
Set-Service -Name "wuauserv" -StartupType Automatic -ErrorAction SilentlyContinue
Write-Host "Service 'wuauserv' set to Automatic startup."

StartAndVerifyService -ServiceName "bits"
Set-Service -Name "bits" -StartupType Automatic -ErrorAction SilentlyContinue
Write-Host "Service 'bits' set to Automatic startup."

StartAndVerifyService -ServiceName "cryptsvc"
Set-Service -Name "cryptsvc" -StartupType Automatic -ErrorAction SilentlyContinue
Write-Host "Service 'cryptsvc' set to Automatic startup."

Write-Host "======================================="
Write-Host "Windows Update Cache Cleanup complete."
Write-Host "======================================="
