<#
.NOTES
	Author	:	Original by Chris Titus @christitustech, Modified by Merion IT Admin
	Version :	Optimized for Windows 10
	Target OS: Windows 10 (latest version)

	This script removes common pre-installed and sponsored applications (bloatware)
	from Windows 10 installations. It targets AppX packages and some traditional
	MSI/program installations.
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Removing Bloatware for Windows 10..."
Write-Host "======================================="

# List of AppX packages to remove for Windows 10.
# Names are often partial for broader matching using wildcards.
# Be cautious: Uncommenting certain lines might remove applications you use (e.g., Photos, Calculator, Store).
$AppXBloatware = @(
	"Microsoft.BingFinance"
	"Microsoft.BingNews"
	"Microsoft.BingSports"
	"Microsoft.BingTranslator"
	"Microsoft.BingWeather"
	"Microsoft.BingFoodAndDrink" # Less common on newer builds, but included for completeness
	"Microsoft.BingHealthAndFitness" # Less common on newer builds, but included for completeness
	"Microsoft.BingTravel" # Less common on newer builds, but included for completeness
	"Microsoft.MinecraftUWP"
	"Microsoft.GamingServices"
	"Microsoft.MicrosoftSolitaireCollection"
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
	"Microsoft.XboxApp"
	"Microsoft.ConnectivityStore"
	"Microsoft.Xbox.TCUI"
	"Microsoft.XboxGameOverlay"
	"Microsoft.XboxSpeechToTextOverlay"
	"Microsoft.MixedReality.Portal"
	"Microsoft.XboxIdentityProvider"
	"Microsoft.ZuneMusic"
	"Microsoft.ZuneVideo"
	"Microsoft.MicrosoftOfficeHub"

	# Sponsored/Featured AppX Apps common on Windows 10
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
	"*HotspotShieldFreeVPN*"
	"*Disney*"
	"*kindle*"
	"*spotify*"
	"*whatsapp*"
	"*tiktok*"
	"*instagram*"
	"*prime*"
	"*PartnerPromo*"
	"*LinkedIn*"
	"*xbox*"


	# Optional AppX Packages (typically not removed by default, uncomment if needed)
	"*Microsoft.Advertising.Xaml*"
	#"*Microsoft.MSPaint*"
	#"*Microsoft.MicrosoftStickyNotes*"
	#"*Microsoft.Windows.Photos*"
	#"*Microsoft.WindowsCalculator*"
	#"*Microsoft.WindowsStore*"
)

# List of traditional programs to remove (e.g., OEM bloatware)
# These are commonly found on Dell and HP machines.
#
# Dell Command Update is deliberately NOT in this list. It used to be ("*DellCommandUpdate*" and
# "*Dellcommand*"), back when DCU was pure nagware. tweaks\vendor-drivers.ps1 now owns DCU - it
# installs it and silences it - so removing it here just breaks the driver path. Observed on
# MRM8035-LT101 2026-09-23: step 4 uninstalled the DCU that step 14 then could not find, leaving
# the machine with SupportAssist gone AND DCU gone, i.e. no OEM driver tooling at all.
# Dell Optimizer stays on the list; it is separate from DCU and is still unwanted.
$TraditionalBloatwarePrograms = @(
	"*DellDigitalDelivery*"
	"*optimizer*"
	"*digialdelivery*"
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
	# Note: HPSystemInformation is listed twice in original, consolidated here.
)

Write-Host "Removing AppX Bloatware Apps..."
foreach ($BloatItem in $AppXBloatware) {
    Write-Host "Attempting to remove AppX: '$BloatItem'..."
    # Attempt to remove for current user
    Get-AppxPackage -Name $BloatItem -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
    # Attempt to de-provision for all new users
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $BloatItem | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}
Write-Host "Finished removing AppX Bloatware Apps."
Write-Host "======================================="

Write-Host "Removing Traditional Bloatware Programs..."
# This section uses Get-Package (from PackageManagement module) to find and uninstall programs.
foreach ($ProgramName in $TraditionalBloatwarePrograms) {
    Write-Host "Attempting to uninstall program: '$ProgramName'..."
    Try {
        Get-Package -Name $ProgramName -ErrorAction SilentlyContinue | Uninstall-Package -AllVersions -Force -ErrorAction SilentlyContinue
        Write-Host "Successfully uninstalled: '$ProgramName'"
    }
    Catch {
        Write-Warning "Failed to uninstall: '$ProgramName'. Error: $($_.Exception.Message)"
    }
}

# Additional checks for common leftover bloatware keywords
if (Get-Package -Name "*optimizer*" -ErrorAction SilentlyContinue) {
    Write-Host "Found and uninstalling remaining '*optimizer*' programs..."
    Get-Package -Name "*optimizer*" | Uninstall-Package -Force -ErrorAction SilentlyContinue
}
# Catches Dell Command | Configure, Dell Command | Monitor, etc. Dell Command | Update is
# excluded on purpose - see the note on $TraditionalBloatwarePrograms above.
$leftoverCommand = Get-Package -Name "*command*" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*Command*Update*" }
if ($leftoverCommand) {
    Write-Host "Found and uninstalling remaining '*command*' programs (keeping Dell Command | Update)..."
    $leftoverCommand | Uninstall-Package -Force -ErrorAction SilentlyContinue
}
if (Get-Package -Name "*delivery*" -ErrorAction SilentlyContinue) {
    Write-Host "Found and uninstalling remaining '*delivery*' programs..."
    Get-Package -Name "*delivery*" | Uninstall-Package -Force -ErrorAction SilentlyContinue
}
Write-Host "Finished removing Traditional Bloatware Programs."
Write-Host "======================================="
Write-Host "Bloatware removal script complete for Windows 10."
