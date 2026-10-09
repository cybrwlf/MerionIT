@echo off
setlocal
title MerionIT - rename this PC

REM One-off rename before (or without) running Setup.bat. Stages the rename, tells you to pull the
REM USB stick, and only restarts when you press Enter. Setup.bat does its own rename and is unaffected.
REM Usage: Rename-PC.bat            (prompts for everything)
REM        Rename-PC.bat -Company MRM -Property 8075
REM Same one-process Bypass as Setup.bat.

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

powershell.exe -ExecutionPolicy Bypass -File "%~dp0manual\Rename-Only.ps1" %*
pause
