$Bloatware = @(


	#Unnecessary Windows 10 AppX Apps
	#"Microsoft.3DBuilder"
	#"Microsoft.Microsoft3DViewer"
	#"Microsoft.AppConnector"
	"Microsoft.BingFinance"
	"Microsoft.BingNews"
	"Microsoft.BingSports"
	"Microsoft.BingTranslator"
	"Microsoft.BingWeather"
	"Microsoft.BingFoodAndDrink"
	"Microsoft.BingHealthAndFitness"
	"Microsoft.BingTravel"
	"Microsoft.MinecraftUWP"
	"Microsoft.GamingServices"
	#"Microsoft.WindowsReadingList"
	#"Microsoft.GetHelp"
	#"Microsoft.Getstarted"
	#"Microsoft.Messaging"
	#"Microsoft.Microsoft3DViewer"
	"Microsoft.MicrosoftSolitaireCollection"
	#"Microsoft.NetworkSpeedTest"
	"Microsoft.News"
	"Microsoft.Office.Lens"
	"Microsoft.Office.Sway"
	"Microsoft.Office.OneNote"
	"Microsoft.OneConnect"
	"Microsoft.People"
	"Microsoft.Print3D"
	"Microsoft.SkypeApp"
	"Microsoft.Wallet"
	"Microsoft.Whiteboard"
	#"Microsoft.WindowsAlarms"
	#"microsoft.windowscommunicationsapps"
	#"Microsoft.WindowsFeedbackHub"
	#"Microsoft.WindowsMaps"
	#"Microsoft.WindowsPhone"
	#"Microsoft.WindowsSoundRecorder"
	"Microsoft.XboxApp"
	"Microsoft.ConnectivityStore"
	#"Microsoft.CommsPhone"
	#"Microsoft.ScreenSketch"
	"Microsoft.Xbox.TCUI"
	"Microsoft.XboxGameOverlay"
	#"Microsoft.XboxGameCallableUI"
	"Microsoft.XboxSpeechToTextOverlay"
	"Microsoft.MixedReality.Portal"
	"Microsoft.XboxIdentityProvider"
	"Microsoft.ZuneMusic"
	"Microsoft.ZuneVideo"
	#"Microsoft.YourPhone"
	#"Microsoft.Getstarted"
	"Microsoft.MicrosoftOfficeHub"

	#Sponsored Windows 10 AppX Apps
	#Add sponsored/featured apps to remove in the "*AppName*" format
	"*EclipseManager*"
	"*ActiproSoftwareLLC*"
	"*AdobePhotoshopExpress*"
	"*Duolingo*"
	"*PandoraMediaInc*"
	"*CandyCrush*"
	"*BubbleWitch3Saga*"
	"*Wunderlist*"
	"*Flipboard*"
	"*Twitter*"
	"*Facebook*"
	"*Royal Revolt*"
	"*Saga*"
	"*Sway*"
	"*Speed Test*"
	"*Dolby*"
	"*Viber*"
	"*ACGMediaPlayer*"
	"*Netflix*"
	"*OneCalendar*"
	"*LinkedInforWindows*"
	"*HiddenCityMysteryofShadows*"
	"*Hulu*"
	"*HiddenCity*"
	"*AdobePhotoshopExpress*"
	"*HotspotShieldFreeVPN*"
	"*Disney*"
	"*kindle*"
	"*spotify*"
	"*whatsapp*"
	"*tiktok*"
	"*instagram*"
	"*prime*"
	"*PartnerPromo*"

	# DELL Bloatware Packages
	"*DellCommandUpdate*"
	"*DellDigitalDelivery*"
	"*optimizer*"
	"*Dellcommand*"
	"*digialdelivery*"
	"*MyDell*"

	# HPBloatware Packages
	"HPJumpStarts"
	"HPPCHardwareDiagnosticsWindows"
	"HPPowerManager"
	"HPPrivacySettings"
	"HPSupportAssistant"
	"HPSureShieldAI"
	"HPSystemInformation"
	"HPQuickDrop"
	"HPWorkWell"
	"myHP"
	"HPDesktopSupportUtilities"
	"HPQuickTouch"
	"HPEasyClean"
	"HPSystemInformation"

	#Optional: Typically not removed but you can if you need to for some reason
	"*Microsoft.Advertising.Xaml*"
	#"*Microsoft.MSPaint*"
	#"*Microsoft.MicrosoftStickyNotes*"
	#"*Microsoft.Windows.Photos*"
	#"*Microsoft.WindowsCalculator*"
	#"*Microsoft.WindowsStore*"
)





Write-Host "Removing Bloatware"

Write-Host "Windows 10 Orginal"
function removebloat()
{
    foreach ($Bloat in $Bloatware) {
        Get-AppxPackage -Name $Bloat| Remove-AppxPackage
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Bloat | Remove-AppxProvisionedPackage -Online
        Write-Host "Trying to remove $Bloat."
        #$ResultText.text = "`r`n" +"`r`n" + "Trying to remove $Bloat."
    }

    Write-Host "Finished Removing Bloatware Apps"
    #$ResultText.text = "`r`n" +"`r`n" + "Finished Removing Bloatware Apps"
}
removebloat
Write-Host "Finished Removing Windows 10 Orginal"

Write-Host "Removing Bloatware Apps"
foreach ($Bloat in $Bloatware) {
                Get-AppxPackage "*$Bloat*" | Remove-AppxPackage -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$Bloat*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                Write-Host "Trying to remove $Bloat."
            }

Write-Host "Finished Removing Bloatware Apps"


Write-Host "Removing Bloatware Programs"

            $InstalledPrograms = Get-Package | Where-Object { $UninstallPrograms -contains $_.Name }
            $InstalledPrograms | ForEach-Object {

                Write-Host -Object "Attempting to uninstall: [$($_.Name)]..."

                Try {
                    $Null = $_ | Uninstall-Package -AllVersions -Force -ErrorAction SilentlyContinue
                    Write-Host -Object "Successfully uninstalled: [$($_.Name)]"
                }
                Catch {
                    Write-Warning -Message "Failed to uninstall: [$($_.Name)]"
                }
            }

			
Write-Host "Finished Removing Bloatware Programs"



if (Get-Package -Name "*optimizer*" -ErrorAction SilentlyContinue) {
    Get-Package -Name "*optimizer*" | Uninstall-Package -Force
}
if (Get-Package -Name "*command*" -ErrorAction SilentlyContinue) {
    Get-Package -Name "*command*" | Uninstall-Package -Force
}
if (Get-Package -Name "*delivery*" -ErrorAction SilentlyContinue) {
    Get-Package -Name "*delivery*" | Uninstall-Package -Force
}
