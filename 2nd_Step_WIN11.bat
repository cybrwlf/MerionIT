@echo off
cd /d "C:\MerionIT"

echo Detected
powershell.exe -Command "(Get-ComputerInfo).OsName" | findstr /i "Windows"
echo -----
ping 127.0.0.1 -n 5 > nul

echo [Step 1 of 16] Turning off "get even more out of Windows" suggestions...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\TurnOFFgetevenmoreoutofwindows.ps1
echo [Step 2 of 16] Applying general Win10/11 tweaks (this one takes a while - O^&O ShutUp, services, telemetry)...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\basic10-11stuff.ps1
echo [Step 3 of 16] Clearing Start Menu recommendations/pinned items...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN11-ClearStartMenu.ps1
echo [Step 4 of 16] Removing bloatware (AppX + OEM programs)...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN11-removebloat-appx.ps1
echo [Step 5 of 16] Verifying Xbox/Dell Optimizer/WhatsApp are actually gone...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-verify-uninstalls.ps1
echo [Step 6 of 16] Checking for McAfee (OEM trial)...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\remove-mcafee.ps1
echo [Step 7 of 16] Removing Teams chat icon...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-remove-teamschaticon.ps1
echo [Step 8 of 16] Setting screensaver...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-screensaver.ps1
echo [Step 9 of 16] Applying taskbar/Explorer tweaks...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-startmenu-left.ps1
echo [Step 10 of 16] Disabling taskbar widgets...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-Disable-Taskbar-Widgets.ps1
echo [Step 11 of 16] Disabling search highlights...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-search-highlights-off.ps1
echo [Step 12 of 16] Unpinning Microsoft Store and Solitaire from Start Menu...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-unpin-startmenu-items.ps1

ping 127.0.0.1 -n 5 > nul

echo Universal Windows Changes
rem powershell.exe -ExecutionPolicy UnRestricted -File tweaks\numlockon.ps1
echo [Step 13 of 16] Cleaning Windows Update cache...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\Clean_win_updates_cache.ps1
echo [Step 14 of 16] Vendor drivers (Dell Command Update, or Windows Update elsewhere)...
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\vendor-drivers.ps1
echo [Step 15 of 16] Applying power configuration...
Start cmd.exe /c call powerconfig.cmd
ping 127.0.0.1 -n 5 > nul

rem Provisioning checks its own work. The recurring failure across this toolkit has been scripts
rem reporting success without verifying it. Anything still wrong lands in Manual-Steps-Reminder.txt,
rem which opens in Notepad on the next line - so a machine cannot leave IT with a broken update
rem policy that nobody saw.
echo [Step 16 of 16] Verifying Windows Update policy...
powershell.exe -ExecutionPolicy UnRestricted -File tools\Repair-MerionWindowsUpdate.ps1 -AddToReminder

echo All steps complete.
notepad.exe "C:\MerionIT\Manual-Steps-Reminder.txt"
