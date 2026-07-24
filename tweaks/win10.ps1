# Run two.ps1 and wait for it to complete
Write-Host Detected OS: (Get-ComputerInfo).OsName
sleep 5

Write-Host "Turn OFF 'get even more out of windows'" 
Start-Process -FilePath "powershell.exe" -ArgumentList "-File TurnOFFgetevenmoreoutofwindows.ps1" -Wait
sleep 5

Write-Host "Basic 10 Stuff" 
powershell.exe -ExecutionPolicy UnRestricted -File basic10-11stuff.ps1
sleep 5

Write-Host "ClearStartMenu" 
powershell.exe -ExecutionPolicy UnRestricted -File ClearStartMenu.ps1
sleep 5

Write-Host "removebloat" 
powershell.exe -ExecutionPolicy UnRestricted -File removebloat-appx.ps1
sleep 5

Write-Host "screensaver" 
powershell.exe -ExecutionPolicy UnRestricted -File win10-screensaver.ps1
sleep 5

Write-Host "clean batch files" 

# Run batch file and wait for it to complete
Start-Process -FilePath "cmd.exe" -ArgumentList "/C .\Clean_win_updates_cache.bat" -Wait
Start-Process -FilePath "cmd.exe" -ArgumentList "/C .\unpin.bat" -Wait
Start-Process -FilePath "cmd.exe" -ArgumentList "/C .\powerconfig.cmd" -Wait


# Continue with the rest of the code in one.ps1
Write-Host "two.ps1 and the batch file have completed, and now one.ps1 continues."
