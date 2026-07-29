@echo off
REM Run as Administrator. Bypasses this machine's script-execution restriction for this one
REM invocation only - does not change the system's execution policy permanently. Every script
REM 1st_Step.ps1 calls internally (RenamePC.ps1, DefaultAccounts.ps1, Agent-Install.ps1,
REM Install-Apps.ps1, Fix-OfficeLanguages.ps1, tweaks\bginfo.ps1) inherits this same override
REM automatically - confirmed live 2026-07-29 that nested "& file.ps1" calls within an already
REM -Bypass'd process do not need their own separate flag.
powershell.exe -ExecutionPolicy Bypass -File "%~dp01st_Step.ps1"
pause
