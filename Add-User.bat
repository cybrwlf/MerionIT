@echo off
setlocal
title MerionIT - add a user

REM New hire at an already-set-up desk: adds one named local account without re-running setup.
REM Usage: Add-User.bat <username>   (prompts for the rest). Same one-process Bypass as Setup.bat.

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

powershell.exe -ExecutionPolicy Bypass -File "%~dp0manual\SingleUser.ps1" %*
pause
