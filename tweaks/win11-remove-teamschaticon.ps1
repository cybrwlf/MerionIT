Write-Host "Disable Microsoft Teams App from Installing..."
If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\MicrosoftTeams_8wekyb3d8bbwe")) {
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\MicrosoftTeams_8wekyb3d8bbwe" -Force
            }

Write-Host "Remove Chat Icon from Taskbar..."
If (!(Test-Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Chat")) {
                New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Chat" -Force
            }
	Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Chat"	 -Name "ChatIcon" -Type DWord -Value 00000003

Write-Host "Disable Microsoft Teams Chat..."
If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force
            }
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Type DWord -Value 00000000