@echo off
setlocal
title MerionIT - reset a laptop for a new user

REM Runs Reset-ForNewUser.ps1 next to this file, as Administrator, with a one-process ExecutionPolicy Bypass.
REM Usage: Reset-ForNewUser.bat -WhatIf   (look first), then Reset-ForNewUser.bat   (asks once before changing anything)
REM Anything on the command line goes to the script: -UsbRoot E: , -SkipRefresh , -Collect

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Not running as Administrator, relaunching elevated...
    if "%~1"=="" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

if not exist "%~dp0Reset-ForNewUser.ps1" (
    echo Reset-ForNewUser.ps1 not found next to this file in %~dp0
    pause
    exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reset-ForNewUser.ps1" %*
echo.
echo Exit code %errorlevel%  (0 = done, 2 = stopped or something needs a look, see the log)
pause
