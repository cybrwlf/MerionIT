
$Merion2Install = @(
    #Windows 10 Apps to install for Merion
    "Zoom.Zoom"
    "Google.Chrome"
    "7zip.7zip"
    "Adobe.Acrobat.Reader.64-bit"
	#"Malwarebytes.Malwarebytes"
    	#"Microsoft.Teams"
	#"Microsoft.OneDrive"
	#"Logitech.UnifyingSoftware"
	#"Notepad++.Notepad++"
	#"Microsoft.PowerToys"
	#"PuTTY.PuTTY"
	#"Python.Python.3"
	#"Microsoft.WindowsTerminal"

	#"CPUID.CPU-Z"
	#"GOG.Galaxy"
	#"TechPowerUp.GPU-Z"
	#"Inkscape.Inkscape"
	#"Valve.Steam"
	#"TeamViewer.TeamViewer"

	#"JAMSoftware.TreeSize.Free"
	#"Microsoft.VisualStudio.2022.Community"

	)


	
function InstallMerion()
{
    Write-Host "Installing Apps For Merion"

    foreach ($Item2Install in $Merion2Install) {
		
		Write-Host "Trying to install $Item2Install."
		$i2icheck =  Read-Host "Install "$Item2Install"? [Y/N]"
		$i2icheck = $i2icheck.ToUpper()
		
		if ( "Y" -eq $i2icheck ){
		winget install -e --id $Item2Install
        } else {
		Write-Warning "Not Installing $Item2Install"}
    }

    Write-Host "Finished Installing Apps For Merion"
}
InstallMerion
