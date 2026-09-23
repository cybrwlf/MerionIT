<#
.NOTES
	Author	:	Original by Chris Titus @christitustech, Modified by Merion IT Admin
	Version :	Optimized for Windows 11
	Target OS: Windows 11 (latest version)

	This script removes common pre-installed and sponsored applications (bloatware)
	from Windows 11 installations. It targets AppX packages and some traditional
	MSI/program installations.
	Note: Windows 11 has a different set of default apps and behaviors.
	Full removal of all desired "bloat" may require ongoing updates to the AppX list
	as Microsoft frequently changes package names or introduces new integrations.
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Removing Bloatware for Windows 11..."
Write-Host "======================================="

# List of AppX packages to remove for Windows 11.
# This list is tailored with common Win11 bloatware in mind, and also includes general ones.
# Be cautious: Uncommenting certain lines might remove applications you use (e.g., Photos, Calculator, Store).
$AppXBloatware = @(
	# Bing/News related
	"Microsoft.BingFinance"
	"Microsoft.BingNews"
	"Microsoft.News"
	"Microsoft.Edge" # While this is Edge, some might consider it removable if using another browser
	"Microsoft.WebExperience" # Often associated with widgets, search, etc.

	# Gaming and Xbox related
	"Microsoft.GamingServices"
	"Microsoft.GamingApp" # Modern Xbox app - "Microsoft.XboxApp" below is the old package name, no longer used
	"Microsoft.XboxGameCallableUI" # Framework the modern Xbox app depends on
	"Microsoft.MinecraftUWP"
	"Microsoft.XboxApp"
	"Microsoft.Xbox.TCUI"
	"Microsoft.XboxGameOverlay"
	"Microsoft.XboxSpeechToTextOverlay"
	"Microsoft.XboxIdentityProvider"
	"Microsoft.XboxGipSvc" # Xbox Accessory Management Service
	"Microsoft.ZuneMusic" # Groove Music
	"Microsoft.ZuneVideo" # Movies & TV

	# Office/Productivity related
	"Microsoft.MicrosoftOfficeHub" # Office Hub app
	"Microsoft.Office.OneNote"
	"Microsoft.Office.Sway"
	"Microsoft.Office.Lens"
	"Microsoft.People"
	"Microsoft.Whiteboard"
	"Microsoft.Wallet" # Less relevant in Win11 UI

	# Communication/Social
	"Microsoft.SkypeApp"
	"Microsoft.Teams" # The new Teams 2.0 / Teams for personal is often installed as AppX
	"Microsoft.YourPhone" # Often referred to as Phone Link now

	# Mixed Reality / 3D
	"Microsoft.MixedReality.Portal"
	"Microsoft.Print3D"
	"Microsoft.3DViewer"

	# General Windows Experience
	"Microsoft.AppConnector" # Often seen as legacy/unnecessary
	"Microsoft.ConnectivityStore" # Related to Wi-Fi Sense, etc.
	"Microsoft.GetHelp"
	"Microsoft.Getstarted"
	#"Microsoft.ScreenSketch" # Screenshot tool, but some prefer alternatives

	# Sponsored/Featured AppX Apps (common across both, but especially pre-installed on new machines)
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
Write-Host "Bloatware removal script complete for Windows 11."
