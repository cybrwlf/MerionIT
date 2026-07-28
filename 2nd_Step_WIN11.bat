@echo off
cd /d "C:\MerionIT"

echo Detected
powershell.exe -Command "(Get-ComputerInfo).OsName" | findstr /i "Windows"
echo -----
ping 127.0.0.1 -n 5 > nul

powershell.exe -ExecutionPolicy UnRestricted -File tweaks\TurnOFFgetevenmoreoutofwindows.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\basic10-11stuff.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN11-ClearStartMenu.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN11-removebloat-appx.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-remove-teamschaticon.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-screensaver.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win11-startmenu-left.ps1

ping 127.0.0.1 -n 5 > nul

echo Universal Windows Changes
rem powershell.exe -ExecutionPolicy UnRestricted -File tweaks\numlockon.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\Clean_win_updates_cache.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN11-Unpin-Taskbar-Items.ps1
Start cmd.exe /c call powerconfig.cmd
ping 127.0.0.1 -n 5 > nul
