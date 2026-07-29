Write-Host "Checking if Winget is Installed..."
        if (Test-Path ~\AppData\Local\Microsoft\WindowsApps\winget.exe) {
            #Checks if winget executable exists and if the Windows Version is 1809 or higher
            Write-Host "Winget Already Installed"
        }
        else {
		# 2023
		Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
		Install-Script -Name winget-install -Force
		winget-install.ps1
		}

