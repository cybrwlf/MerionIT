@echo off
setlocal
cd /d "C:\MerionIT"
if not exist "C:\MerionIT\logs" mkdir "C:\MerionIT\logs"
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "TS=%%T"
set "LOGFILE=C:\MerionIT\logs\3rd_Step_WIN10-%TS%.log"

(
echo Detected
powershell.exe -Command "(Get-ComputerInfo).OsName" | findstr /i "Windows"

echo -----
ping 127.0.0.1 -n 5 > nul

powershell.exe -ExecutionPolicy UnRestricted -File tweaks\TurnOFFgetevenmoreoutofwindows.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\basic10-11stuff.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN10-ClearStartMenu.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN10-removebloat-appx.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\win10-screensaver.ps1

ping 127.0.0.1 -n 5 > nul

echo Universal Windows Changes
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\numlockon.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\Clean_win_updates_cache.ps1
powershell.exe -ExecutionPolicy UnRestricted -File tweaks\WIN10-Unpin-Taskbar-Items.ps1
Start cmd.exe /c call powerconfig.cmd

ping 127.0.0.1 -n 5 > nul
) 2>&1 | powershell -NoProfile -Command "$input | Tee-Object -FilePath '%LOGFILE%'"
