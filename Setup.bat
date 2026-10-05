@echo off
setlocal
title MerionIT setup

REM Double-click this on a new or half-set-up machine. It works out where the scripts should come
REM from, puts them in C:\MerionIT, then starts Step 1. Safe to re-run at any time.
REM
REM   Run from a folder that holds the repo (USB stick, a copy in Downloads)
REM       -> copies that folder into C:\MerionIT (copy only, nothing on C: is deleted)
REM   Run from C:\MerionIT, or as a lone file, and GitHub is reachable
REM       -> pulls the latest scripts from GitHub into C:\MerionIT
REM   No internet
REM       -> uses whatever is already in C:\MerionIT
REM
REM   Setup.bat /local   skip the GitHub pull and use what is already in C:\MerionIT
REM                      (use this when you have hand-copied newer scripts than GitHub has)
REM   Anything else on the line is passed to Step 1, e.g.
REM       Setup.bat -ForceRename -Unattended -Company MRM -Property 1234 -Year 2026 -NoReboot
REM
REM Why a batch file: a new Windows install blocks .ps1 scripts by default, so PowerShell is only
REM ever started with -ExecutionPolicy Bypass for that one process. Nothing is changed permanently,
REM and every script Step 1 calls inherits the override.

net session >nul 2>&1
if %errorlevel% neq 0 goto :elevate

set "SRC=%~dp0"
set "DEST=C:\MerionIT"
set "STEP1=%DEST%\setup\Step1-Accounts-Apps.ps1"
set "URL=https://raw.githubusercontent.com/cybrwlf/MerionIT/master/bootstrap.ps1"
set "LOCAL="
set "PASS="

:argloop
if "%~1"=="" goto :argdone
if /i "%~1"=="/local" (set "LOCAL=1") else (set PASS=%PASS% %1)
shift
goto :argloop
:argdone

REM Run from some other folder that holds the repo: copy it in, no internet needed.
if /i "%SRC%"=="%DEST%\" goto :fromdest
if not exist "%SRC%setup\Step1-Accounts-Apps.ps1" goto :fromdest
echo Copying %SRC% to %DEST% ...
robocopy "%SRC%." "%DEST%" /E /XD .git /NFL /NDL /NJH /NP
if %errorlevel% geq 8 goto :copyfail
goto :launch

:fromdest
if defined LOCAL goto :launch
echo Checking GitHub and pulling the latest scripts into %DEST% ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 '%URL%'))) -NoLaunch"
if %errorlevel% neq 0 echo GitHub pull did not work - continuing with whatever is already in %DEST%.
goto :launch

:launch
if not exist "%STEP1%" goto :nofiles
if not exist "%DEST%\secrets.psd1" (
    echo.
    echo WARNING: no secrets.psd1 in %DEST%. Account setup will fail without it.
    echo          Copy it into %DEST% first, then press a key to continue.
    pause
)
echo.
echo Starting Step 1...
powershell.exe -ExecutionPolicy Bypass -File "%STEP1%"%PASS%
pause
exit /b

:nofiles
echo ERROR: no scripts in %DEST% and no way to get them. Connect to the internet, or run this from a folder that holds the repo.
pause
exit /b 1

:copyfail
echo ERROR: copy to %DEST% failed, robocopy exit code %errorlevel%. Not starting setup.
pause
exit /b 1

:elevate
echo Not running as Administrator, relaunching elevated...
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
)
exit /b
