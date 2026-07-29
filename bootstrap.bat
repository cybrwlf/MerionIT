@echo off
REM Run as Administrator. Double-click entry point so a tech never needs to type/paste a
REM PowerShell one-liner or touch execution policy manually. Bypasses this machine's
REM script-execution restriction for this one invocation only - does not change the system's
REM execution policy permanently. bootstrap.ps1's own later call into 1st_Step.ps1 inherits this
REM same override automatically (same process, confirmed live 2026-07-29).
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/cybrwlf/MerionIT/master/bootstrap.ps1 | iex"
pause
