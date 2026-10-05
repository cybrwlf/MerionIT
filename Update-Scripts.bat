@echo off
setlocal
title MerionIT - update scripts

REM Pulls the latest scripts from GitHub into C:\MerionIT and starts nothing. Use it on a machine
REM that is already set up (or partway), or from Kaseya, when you only want the newest files.
REM Same one-process -ExecutionPolicy Bypass as Setup.bat. Needs internet.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Not running as Administrator, relaunching elevated...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 'https://raw.githubusercontent.com/cybrwlf/MerionIT/master/bootstrap.ps1'))) -NoLaunch"
if %errorlevel% neq 0 echo ERROR: update failed - check the machine can reach raw.githubusercontent.com.
pause
