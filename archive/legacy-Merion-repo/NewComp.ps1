Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'SilentlyContinue'
$wshell = New-Object -ComObject Wscript.Shell
$Button = [System.Windows.MessageBoxButton]::YesNoCancel
$ErrorIco = [System.Windows.MessageBoxImage]::Error
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
	Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
	Exit
}

	

# GUI Specs
Write-Host "Checking winget..."

# Check if winget is installed
if (Test-Path ~\AppData\Local\Microsoft\WindowsApps\winget.exe){
    'Winget Already Installed'
}  
else {
	#Gets the computer's information
	$ComputerInfo = Get-ComputerInfo

	#Gets the Windows Edition
	$OSName = if ($ComputerInfo.OSName) {
		$ComputerInfo.OSName
	}else {
		$ComputerInfo.WindowsProductName
	}

	if (((($OSName.IndexOf("LTSC")) -ne -1) -or ($OSName.IndexOf("Server") -ne -1)) -and (($ComputerInfo.WindowsVersion) -ge "1809")) {
		
		Write-Host "Running Alternative Installer for LTSC/Server Editions"

		# Switching to winget-install from PSGallery from asheroto
		# Source: https://github.com/asheroto/winget-installer
		
		Start-Process powershell.exe -Verb RunAs -ArgumentList "-command irm https://raw.githubusercontent.com/asheroto/winget-installer/master/winget-install.ps1 | iex | Out-Host" -WindowStyle Normal
		
	}
	elseif (((Get-ComputerInfo).WindowsVersion) -lt "1809") {
		#Checks if Windows Version is too old for winget
		Write-Host "Winget is not supported on this version of Windows (Pre-1809)"
	}
	else {
		#Installing Winget from the Microsoft Store
		Write-Host "Winget not found, installing it now."
		Start-Process "ms-appinstaller:?source=https://aka.ms/getwinget"
		$nid = (Get-Process AppInstaller).Id
		Wait-Process -Id $nid
		Write-Host "Winget Installed"
	}
}




$Merion2Install = @(
	#Windows 10 Apps to install for Merion
	"Zoom.Zoom"
	"Google.Chrome"
	#"Microsoft.Teams"
	#"Microsoft.OneDrive"
	"7zip.7zip"
	#"Logitech.UnifyingSoftware"
	"Adobe.Acrobat.Reader.64-bit"
	#"Microsoft.WindowsTerminal"
	#"Malwarebytes.Malwarebytes"
	#"Rufus.Rufus"
	#"TeamViewer.TeamViewer"
	#"Microsoft.Teams"
	#"JAMSoftware.TreeSize.Free"
	#"Microsoft.VisualStudio.2022.Community"
	)

	function InstallMerion()
	{
		Write-Host "Installing Apps For Merion"
	
		foreach ($Item2Install in $Merion2Install) {
			
			Write-Host "Trying to install $Item2Install."
			try {
				Start-Process powershell.exe -Verb RunAs -ArgumentList "-command winget upgrade -e --accept-source-agreements --accept-package-agreements --silent $Item2Install | Out-Host" -WindowStyle Normal
				$wingetResult.Add("$Item2Install`n")
				Start-Sleep -s 3
				Wait-Process winget -Timeout 90 -ErrorAction SilentlyContinue
			} catch {
			
			
			$ButtonType = [System.Windows.MessageBoxButton]::OK
			if ($wingetResult -ne "") {
				$Messageboxbody = "Installed Programs `n$($Item2Install)"
			}
			else {
				winget install -e --id $Item2Install
				Start-Sleep -s 3
				Wait-Process winget -Timeout 90 -ErrorAction SilentlyContinue
				
			}
			$MessageIcon = [System.Windows.MessageBoxImage]::Information
	
			[System.Windows.MessageBox]::Show($Messageboxbody, $AppTitle, $ButtonType, $MessageIcon)
		}

			
		}
	
		Write-Host "Finished Installing Apps For Merion"
	}
	InstallMerion



Write-Host "==========================="
Write-Host "---  Script Finished    ---"
Write-Host "==========================="
