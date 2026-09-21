<#
.NOTES
	Author	:	Chris Titus @christitustech
	Modder	:	Merion IT Admin
	Version :	2025.06.11

	This script performs various optimizations and privacy tweaks on Windows 10 and Windows 11.
	It aims to:
	- Create a system restore point.
	- Disable activity history, game DVR, hibernation, location tracking, and TPM check (for upgrades).
	- Clean temporary files and run Disk Cleanup.
	- Adjust notifications, right-click menu, and Explorer view.
	- Enable long paths.
	- Apply performance and network tweaks.
	- Disable News and Interests, Meet Now, and Wi-Fi Sense.
	- Disable telemetry, error reporting, and update P2P.
	- Adjust visual effects for performance.
	- Remove Cortana.
	- Configure Windows Update settings.
	- Tweak Outlook's bottom navigation pane.
	- Disable/configure various Windows services for better performance/privacy.

	Compatibility: Designed for and tested on latest Windows 10 and Windows 11 versions.
	Conditional logic is used for specific build-related behaviors (e.g., Task Manager tweaks).
#>

# Start a transcript to log script execution
# $ENV:ResourceGroup might need to be defined if not running in a specific environment
# Fallback to C:\temp if $ENV:ResourceGroup is not set
$logPath = If ($ENV:ResourceGroup) { "$ENV:ResourceGroup\NewPC-Winutil.log" } else { "C:\temp\NewPC-Winutil.log" }
# Ensure the directory exists
New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null
Start-Transcript -Path $logPath -Append

# ---------------------------------------------------------------------------------------------
# 2026-09-21: this script previously contained two calls that blocked forever when setup was
# driven remotely (SSH, Kaseya, a scheduled task - anything without a desktop), taking the whole
# tweaks stage down with them and silently skipping every step that followed:
#
#   - cleanmgr.exe /VERYLOWDISK     waited on a completion dialog that could never be shown.
#                                   Measured blocked at 18.1 minutes on MRM8065-DT201.
#   - Start-Process taskmgr.exe + an unbounded Do/Until waiting for a registry value Task Manager
#                                   never writes without a desktop.
#
# Neither had a timeout, and the batch files calling this script don't check exit codes, so the
# failure was invisible. Both are now replaced with unattended equivalents - see the comments at
# each site below. Full write-up in MerionIT-PRD.md Known Issue #11.
#
# Lesson worth keeping: nothing in this script may launch a GUI process and wait on it.
# ---------------------------------------------------------------------------------------------

Write-Host "======================================="
Write-Host "Creating Restore Point in case something bad happens"
# Ensure Computer Restore is enabled before creating a restore point
Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
Checkpoint-Computer -Description "RestorePoint1" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
Write-Host "======================================="


Write-Host "======================================="
Write-Host "Disabling Activity History..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Write-Host "======================================="
Write-Host "Delete Temp Files"
Get-ChildItem -Path "C:\Windows\Temp" *.* -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
Get-ChildItem -Path $env:TEMP *.* -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

Write-Host "======================================="
Write-Host "--- Cleaned following folders:"
Write-Host "--- C:\Windows\Temp"
Write-Host "--- $env:TEMP"
Write-Host "======================================="
Write-Host "======================================="
Write-Host "Disabling Game DVR..."
If (!(Test-Path "HKCU:\System\GameConfigStore")) {
    New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_HonorUserFSEBehaviorMode" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_EFSEFeatureFlags" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehavior" -Type DWord -Value 2 -ErrorAction SilentlyContinue
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Write-Host "======================================="
Write-Host "Disabling Hibernation..."
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" -Name "HibernateEnabled" -Type Dword -Value 0 -ErrorAction SilentlyContinue
If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Force | Out-Null # Added -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowHibernateOption" -Type Dword -Value 0 -ErrorAction SilentlyContinue

Write-Host "======================================="
Write-Host "Disabling Location Tracking and Maps updates..."
If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type String -Value "Deny" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\Maps" -Name "AutoUpdateEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Write-Host "======================================="
Write-Host "Disabling TPM Check for upgrades (if applicable)..."
If (!(Test-Path "HKLM:\SYSTEM\Setup\MoSetup")) {
    New-Item -Path "HKLM:\SYSTEM\Setup\MoSetup" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPM" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Write-Host "======================================="
Write-Host "Reclaiming disk space..."
# Replaced cleanmgr.exe /VERYLOWDISK, 2026-09-21. Every cleanmgr mode ends in a dialog or a
# progress window, so none of them are safe without a desktop - /VERYLOWDISK blocked for 18+
# minutes on MRM8065-DT201 and took the whole tweaks stage down with it. /sagerun is the usual
# deployment workaround but still renders a window, which trades a certain hang for a likely one.
#
# These call the same underlying cleanup directly. They run identically interactive or not, so
# every machine gets the same result regardless of how it was built - which cleanmgr never did.
# Component store cleanup is also the larger reclaim by far (typically GBs vs MBs); temp files
# are handled above and the Windows Update cache by Clean_win_updates_cache.ps1 later on.
$dism = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" `
    -NoNewWindow -PassThru
if (-not $dism.WaitForExit(1800000)) {   # 30 min backstop - this one legitimately takes a while
    Write-Warning "Component store cleanup still running after 30 minutes - killing it and moving on."
    Stop-Process -Id $dism.Id -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  Component store cleanup finished (exit $($dism.ExitCode))."
}
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Host "  Recycle Bin emptied."
Write-Host "======================================="
Write-Host "Disabling Notifications and Action Center..."
New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows" -Name "Explorer" -force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableNotificationCenter" -PropertyType "DWord" -Value 0 -force -ErrorAction SilentlyContinue
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -PropertyType "DWord" -Value 0 -force -ErrorAction SilentlyContinue
Write-Host "======================================="
Write-Host "Setting Classic Right-Click Menu (Windows 11 specific tweak)..."
# This tweak is primarily for Windows 11 to revert to the old context menu.
# On Windows 10, it will likely have no effect.
New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Name "InprocServer32" -force -value "" -ErrorAction SilentlyContinue
Write-Host "======================================="
# Check if O&O Shutup 10 executable is present. The config is NOT downloaded - this repo ships
# its own committed copy (tweaks\ooshutup10.cfg) so the actual settings applied are reviewable
# and controlled here, not whatever happens to be live on Chris Titus's GitHub at run time.
# Previously this downloaded a fresh config to ".\ooshutup10.cfg" every run, which silently never
# got used anyway - relative paths here resolve against C:\MerionIT (the batch file's working
# directory), not tweaks\, so the committed config was never actually read until this fix.
Write-Host "Checking for O&O Shutup..."
$OOSUConfig = "$PSScriptRoot\ooshutup10.cfg"
If (!(Test-Path ".\OOSU10.exe")) {
    Write-Host "Downloading O&O Shutup executable"
    try {
        Invoke-WebRequest -Uri "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe" -OutFile "OOSU10.exe" -ErrorAction Stop
    } catch {
        Write-Error "Failed to download OOSU10.exe: $($_.Exception.Message)"
    }
} else {
    Write-Host "O&O Shutup executable found, skipping download."
}
# Run O&O Shutup if executable exists, using this repo's own committed config
If (Test-Path ".\OOSU10.exe") {
    if (Test-Path $OOSUConfig) {
        Write-Host "Running O&O Shutup with the committed config ($OOSUConfig)"
        ./OOSU10.exe $OOSUConfig /quiet
    } else {
        Write-Error "Committed ooshutup10.cfg not found at $OOSUConfig - skipping O&O Shutup rather than falling back to an unreviewed config."
    }
} else {
    Write-Host "OOSU10.exe not found, skipping O&O Shutup execution."
}

Write-Host "======================================="
Write-Host "Setting Services to Manual... "

$services = @(
    "ALG"                                          # Application Layer Gateway Service(Provides support for 3rd party protocol plug-ins for Internet Connection Sharing)
    "AJRouter"                                     # Needed for AllJoyn Router Service
    "BcastDVRUserService_48486de"                  # GameDVR and Broadcast is used for Game Recordings and Live Broadcasts
    #"BDESVC"                                      # Bitlocker Drive Encryption Service
    #"BFE"                                         # Base Filtering Engine (Manages Firewall and Internet Protocol security)
    #"BluetoothUserService_48486de"                # Bluetooth user service supports proper functionality of Bluetooth features relevant to each user session.
    #"BrokerInfrastructure"                        # Windows Infrastructure Service (Controls which background tasks can run on the system)
    "Browser"                                      # Let users browse and locate shared resources in neighboring computers
    "BthAvctpSvc"                                  # AVCTP service (needed for Bluetooth Audio Devices or Wireless Headphones)
    "CaptureService_48486de"                       # Optional screen capture functionality for applications that call the Windows.Graphics.Capture API.
    "cbdhsvc_48486de"                              # Clipboard Service
    "diagnosticshub.standardcollector.service"     # Microsoft (R) Diagnostics Hub Standard Collector Service
    "DiagTrack"                                    # Diagnostics Tracking Service
    #"dmwappushservice"                            # WAP Push Message Routing Service - left at the Windows default; Intune OMA-DM sync depends on it
    "DPS"                                          # Diagnostic Policy Service (Detects and Troubleshoots Potential Problems)
    "edgeupdate"                                   # Edge Update Service
    "edgeupdatem"                                  # Another Update Service
    #"EntAppSvc"                                    # Enterprise Application Management.
    "Fax"                                          # Fax Service
    "fhsvc"                                        # Fax History
    "FontCache"                                    # Windows font cache
    #"FrameServer"                                 # Windows Camera Frame Server (Allows multiple clients to access video frames from camera devices)
    "gupdate"                                      # Google Update
    "gupdatem"                                     # Another Google Update Service
    #"iphlpsvc"                                     # ipv6(Most websites use ipv4 instead) - Needed for Xbox Live
    "lfsvc"                                        # Geolocation Service
    #"LicenseManager"                              # Disable LicenseManager (Windows Store may not work properly)
    "lmhosts"                                      # TCP/IP NetBIOS Helper
    "MapsBroker"                                   # Downloaded Maps Manager
    "MicrosoftEdgeElevationService"                # Another Edge Update Service
    "MSDTC"                                        # Distributed Transaction Coordinator
    "NahimicService"                               # Nahimic Service
    #"ndu"                                          # Windows Network Data Usage Monitor (Disabling Breaks Task Manager Per-Process Network Monitoring)
    "NetTcpPortSharing"                            # Net.Tcp Port Sharing Service
    "PcaSvc"                                       # Program Compatibility Assistant Service
    "PerfHost"                                     # Remote users and 64-bit processes to query performance.
    "PhoneSvc"                                     # Phone Service(Manages the telephony state on the device)
    #"PNRPsvc"                                     # Peer Name Resolution Protocol (Some peer-to-peer and collaborative applications, such as Remote Assistance, may not function, Discord will still work)
    #"p2psvc"                                      # Peer Name Resolution Protocol(Enables multi-party communication using Peer-to-Peer Grouping. If disabled, some applications, such as HomeGroup, may not function. Discord will still work)
    #"p2pimsvc"                                    # Peer Networking Identity Manager (Peer-to-Peer Grouping services may not function, and some applications, such as HomeGroup and Remote Assistance, may not function correctly. Discord will still work)
    "PrintNotify"                                  # Windows printer notifications and extentions
    "QWAVE"                                        # Quality Windows Audio Video Experience (audio and video might sound worse)
    "RemoteAccess"                                 # Routing and Remote Access
    "RemoteRegistry"                               # Remote Registry
    "RetailDemo"                                   # Demo Mode for Store Display
    "RtkBtManServ"                                 # Realtek Bluetooth Device Manager Service
    "SCardSvr"                                     # Windows Smart Card Service
    "seclogon"                                     # Secondary Logon (Disables other credentials only password will work)
    "SEMgrSvc"                                     # Payments and NFC/SE Manager (Manages payments and Near Field Communication (NFC) based secure elements)
    "SharedAccess"                                 # Internet Connection Sharing (ICS)
    #"Spooler"                                     # Printing
    "stisvc"                                       # Windows Image Acquisition (WIA)
    #"StorSvc"                                     # StorSvc (usb external hard drive will not be reconized by windows)
    "SysMain"                                      # Analyses System Usage and Improves Performance
    "TrkWks"                                       # Distributed Link Tracking Client
    #"WbioSrvc"                                    # Windows Biometric Service (required for Fingerprint reader / facial detection)
    "WerSvc"                                       # Windows error reporting
    "wisvc"                                        # Windows Insider program(Windows Insider will not work if Disabled)
    #"WlanSvc"                                     # WLAN AutoConfig
    "WMPNetworkSvc"                                # Windows Media Player Network Sharing Service
    "WpcMonSvc"                                    # Parental Controls
    "WPDBusEnum"                                   # Portable Device Enumerator Service
    "WpnService"                                   # WpnService (Push Notifications may not work)
    #"wscsvc"                                      # Windows Security Center Service
    #"WSearch"                                     # Windows Search - left running (Automatic); the taskbar search box depends on it
    "XblAuthManager"                               # Xbox Live Auth Manager (Disabling Breaks Xbox Live Games)
    "XblGameSave"                                  # Xbox Live Game Save Service (Disabling Breaks Xbox Live Games)
    "XboxNetApiSvc"                                # Xbox Live Networking Service (Disabling Breaks Xbox Live Games)
    "XboxGipSvc"                                   # Xbox Accessory Management Service
    # Hp services
    "HPAppHelperCap"
    "HPDiagsCap"
    "HPNetworkCap"
    "HPSysInfoCap"
    "HpTouchpointAnalyticsService"
    # Hyper-V services
    "HvHost"
    "vmicguestinterface"
    "vmicheartbeat"
    "vmickvpexchange"
    "vmicrdv"
    "vmicshutdown"
    "vmictimesync"
    "vmicvmsession"
    # Services that cannot be disabled
    #"WdNisSvc"
)

foreach ($service in $services) {
    # -ErrorAction SilentlyContinue is so it doesn't write an error to stdout if a service doesn't exist
    Write-Host "Setting $service StartupType to Manual"
    Get-Service -Name $service -ErrorAction SilentlyContinue | Set-Service -StartupType Manual -ErrorAction SilentlyContinue
}
Write-Host "======================================="
Write-Host "Disabling Storage Sense..."
Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Recurse -ErrorAction SilentlyContinue

Write-Host "======================================="
Write-Host "Disabling Telemetry and Application Suggestions..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Disable-ScheduledTask -TaskName "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Application Experience\ProgramDataUpdater" -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Autochk\Proxy" -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "OemPreInstalledAppsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEverEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353698Enabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Write-Host "Disabling Feedback..."
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules")) {
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClient" -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload" -ErrorAction SilentlyContinue | Out-Null
Write-Host "Disabling Tailored Experiences..."
If (!(Test-Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent")) {
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CloudContent" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableTailoredExperiencesWithDiagnosticData" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Write-Host "Disabling Advertising ID..."
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Force | Out-Null # Added -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Write-Host "Disabling Error reporting..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Disable-ScheduledTask -TaskName "Microsoft\Windows\Windows Error Reporting\QueueReporting" -ErrorAction SilentlyContinue | Out-Null
Write-Host "Restricting Windows Update P2P only to local network..."
If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force | Out-Null # Added -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Write-Host "Stopping and disabling Diagnostics Tracking Service..."
Stop-Service "DiagTrack" -WarningAction SilentlyContinue
Set-Service "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
# DO NOT RE-ENABLE: dmwappushservice is the OMA-DM transport for Intune/MDM sync, not telemetry.
# Disabling it kills Intune check-in from day one, silently - it stranded 4 machines in one of
# our tenants for 169-269 days while Entra join, MDM cert and EnrollmentState all looked healthy.
#Write-Host "Stopping and disabling WAP Push Service..."
#Stop-Service "dmwappushservice" -WarningAction SilentlyContinue
#Set-Service "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
Write-Host "Enabling F8 boot menu options..."
bcdedit /set `{current`} bootmenupolicy Legacy | Out-Null

#Write-Host "Disabling Remote Assistance..."
#Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Type DWord -Value 0

Write-Host "Stopping and disabling Superfetch service (SysMain)..."
Stop-Service "SysMain" -WarningAction SilentlyContinue
Set-Service "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue

# Task Manager "more details" tweak REMOVED 2026-09-21 (Ricardo's call). It launched taskmgr.exe
# and waited on an unbounded loop for a registry blob a GUI app only writes when it has a desktop,
# which hung the entire tweaks stage on every remote build - see MerionIT-PRD.md Known Issue #11.
# Deleted rather than repaired because even working it was worth almost nothing: gated to builds
# below 22557 (all now out of support), HKCU-only so it never reached the end user (PRD #13), and
# a no-op on a fresh build where nobody has opened Task Manager under the setup account yet.

Write-Host "Showing file operations details..."
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager")) {
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Force | Out-Null # Added -Force
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Write-Host "Hiding Task View button..."
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Write-Host "Hiding People icon..."
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People")) {
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Force | Out-Null # Added -Force
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Type DWord -Value 0 -ErrorAction SilentlyContinue

Write-Host "Changing default Explorer view to This PC..."
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Type DWord -Value 1 -ErrorAction SilentlyContinue

## Enable Long Paths
Write-Host "Enabling Long Paths..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Type DWORD -Value 1 -ErrorAction SilentlyContinue

Write-Host "Hiding 3D Objects icon from This PC..."
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -ErrorAction SilentlyContinue

## Performance Tweaks and More Telemetry
Write-Host "Applying Performance Tweaks..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "ClearPageFileAtShutdown" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseHoverTime" -Type DWord -Value 400 -ErrorAction SilentlyContinue

## Timeout Tweaks (may cause flickering on Windows now)
Write-Host "Applying Timeout Tweaks (Note: may cause flickering on Windows)..."
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "LowLevelHooksTimeout" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillServiceTimeout" -ErrorAction SilentlyContinue

# Network Tweaks
Write-Host "Applying Network Tweaks..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "IRPStackSize" -Type DWord -Value 20 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Type DWord -Value 4294967295 -ErrorAction SilentlyContinue

# Gaming Tweaks (Commented out in original script)
# Write-Host "Applying Gaming Tweaks (if uncommented)..."
# Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "GPU Priority" -Type DWord -Value 8 -ErrorAction SilentlyContinue
# Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority" -Type DWord -Value 6 -ErrorAction SilentlyContinue
# Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Scheduling Category" -Type String -Value "High" -ErrorAction SilentlyContinue

# Group svchost.exe processes
Write-Host "Grouping svchost.exe processes based on RAM..."
$ram = (Get-CimInstance -ClassName "Win32_PhysicalMemory" | Measure-Object -Property Capacity -Sum).Sum / 1kb
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Type DWord -Value $ram -Force -ErrorAction SilentlyContinue

Write-Host "Disable News and Interests..."
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force | Out-Null # Added -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type DWord -Value 0 -ErrorAction SilentlyContinue
# Remove "News and Interest" from taskbar
Set-ItemProperty -Path  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Type DWord -Value 2 -ErrorAction SilentlyContinue

Write-Host "Removing 'Meet Now' button from taskbar..."
If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -Type DWord -Value 1 -ErrorAction SilentlyContinue

Write-Host "Removing AutoLogger file and restricting directory..."
$autoLoggerDir = "$env:PROGRAMDATA\Microsoft\Diagnosis\ETLLogs\AutoLogger"
If (Test-Path "$autoLoggerDir\AutoLogger-Diagtrack-Listener.etl") {
    Remove-Item "$autoLoggerDir\AutoLogger-Diagtrack-Listener.etl" -ErrorAction SilentlyContinue
}
icacls $autoLoggerDir /deny SYSTEM:`(OI`)`(CI`)F | Out-Null

Write-Host "Stopping and disabling Diagnostics Tracking Service..."
Stop-Service "DiagTrack" -WarningAction SilentlyContinue
Set-Service "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

Write-Host "Doing Security checks for Administrator Account and Group Policy (disabling built-in Admin if not active)..."
if (([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).IndexOf('Administrator') -eq -1) {
    net user administrator /active:no
}

Write-Host "Disabling Wi-Fi Sense..."
If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "Value" -Type DWord -Value 0 -ErrorAction SilentlyContinue
If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Name "Value" -Type DWord -Value 0 -ErrorAction SilentlyContinue

If (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Type DWord -Value 00000000 -ErrorAction SilentlyContinue
}
# Disable Fast Startup - can cause issues with driver updates and network-drive timing at boot.
# Fixed 2026-07-30: this previously set the value to 1 (enabled) with a self-uncertain comment.
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue

Write-Host "Showing known file extensions..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Type DWord -Value 0 -ErrorAction SilentlyContinue

# Merion IT Admin Test Section - These are generally compatible and target common UI elements.
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCortanaButton" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneExpandToCurrentFolder" -Type DWord -Value 1 -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type DWord -Value 0 -ErrorAction SilentlyContinue

# Added 2026-07-30 (via Rufus's Windows User Experience QoL tweaks, see brainstorms\2026-07-30-rufus-qol-tweaks-merionit.md):
Write-Host "Disabling Copilot..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Type DWord -Value 0 -ErrorAction SilentlyContinue
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Type DWord -Value 1 -ErrorAction SilentlyContinue

Write-Host "Disabling Bing web results in taskbar search..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue

Write-Host "Disabling Teams consumer chat auto-install (taskbar icon only - does not affect the real M365 Teams app)..."
If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Name "ConfigureChatAutoInstall" -Type DWord -Value 0 -ErrorAction SilentlyContinue

Write-Host "Skipping Edge's first-run experience..."
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Type DWord -Value 1 -ErrorAction SilentlyContinue

Write-Host "Setting Start Menu to More Pins layout..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Type DWord -Value 1 -ErrorAction SilentlyContinue

# Search Highlights (the animated icon in the search box) is handled by
# tweaks\win11-search-highlights-off.ps1, which actually creates the key first - this line never
# worked (HKLM:\...\Windows Search doesn't exist by default, so Set-ItemProperty silently no-ops
# without a New-Item guard first) and has been removed rather than fixed in three places.

Write-Host "Restarting Explorer to apply UI changes..."
Stop-Process -processName: Explorer -force -ErrorAction SilentlyContinue # This will restart the Explorer service to make this work.
Sleep 5 # Wait 5 Seconds
#Start-Process -processName: Explorer  #Explorer typically restarts automatically after being stopped.

Write-Host "Setting BIOS time to UTC..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" -Name "RealTimeIsUniversal" -Type DWord -Value 1 -ErrorAction SilentlyContinue

Write-Host "Adjusting visual effects for performance..."
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Type String -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Type String -Value 200 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](144, 18, 3, 128, 16, 0, 0, 0)) -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Type String -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Type DWord -Value 3 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Write-Host "Adjusted visual effects for performance"

Write-Host "Removing Cortana..."
Get-AppxPackage -allusers Microsoft.549981C3F5F10 -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue


Write-Host "-- Updates Set to Recommended ---"
Write-Host "Disabling driver offering through Windows Update..."
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Type DWord -Value 1 -ErrorAction SilentlyContinue
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\DriverSearching" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Type DWord -Value 0 -ErrorAction SilentlyContinue
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Force | Out-Null # Added -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Write-Host "Disabling Windows Update automatic restart..."
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -Type DWord -Value 0 -ErrorAction SilentlyContinue
Write-Host "Disabled driver offering through Windows Update"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -Type DWord -Value 20 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -Type DWord -Value 365 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays " -Type DWord -Value 4 -ErrorAction SilentlyContinue

Write-Host "-- Outlook Bottom NavPane ---"
# This section targets Office 2016 (version 16.0).
# The tweak might not apply to newer Office versions.
$KeyPath = "HKCU:\Software\Microsoft\Office\16.0\Common\ExperimentEcs\Overrides"
$ValueName = "Microsoft.Office.Outlook.Hub.HubBar"
$ValueData = "false"
try {
    # Attempt to get the property first to see if it exists
    Get-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction Stop
    Set-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Force -ErrorAction SilentlyContinue
}
catch [System.Management.Automation.ItemNotFoundException] {
    # If key/property not found, create them
    New-Item -Path $KeyPath -Force | Out-Null # Ensure parent key exists
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Force -ErrorAction SilentlyContinue
}
catch {
    # Generic catch for other errors, attempting to create with a string type
    New-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type String -Force -ErrorAction SilentlyContinue
}

# Stop transcript at the end of the script
Stop-Transcript
