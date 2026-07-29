<#
Displays system info on the desktop background via Sysinternals BGInfo. Installs BGInfo via
winget instead of vendoring the .exe (the old process shipped a local BGinfo/ folder with the
binary in it - this fetches it from Microsoft instead). Uses the .bgi config committed alongside
this script (bginfo.bgi). A light-theme variant (bginfo-white.bgi) was never actually wired up
to anything - archived at archive/bginfo-white.bgi if that's wanted later
(pass -ConfigFile "$PSScriptRoot\..\archive\bginfo-white.bgi" to use it).
#>
param(
    [string]$ConfigFile = "$PSScriptRoot\bginfo.bgi"
)

Get-NetAdapterBinding | Where-Object ComponentID -EQ 'ms_tcpip6' | Disable-NetAdapterBinding -ComponentID 'ms_tcpip6'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning "winget not available - cannot install BGInfo automatically. Install it manually from https://learn.microsoft.com/sysinternals/downloads/bginfo"
    return
}

$BgInfoDir = "C:\BGinfo"
New-Item -ItemType Directory -Path $BgInfoDir -Force | Out-Null

winget install --id Microsoft.Sysinternals.BGInfo --source winget --silent --accept-package-agreements --accept-source-agreements --location $BgInfoDir

$bgInfoExe = Get-ChildItem -Path $BgInfoDir -Filter "Bginfo*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bgInfoExe) {
    Write-Error "BGInfo executable not found after winget install."
    return
}

Copy-Item -Path $ConfigFile -Destination "$BgInfoDir\BGinfo.bgi" -Force

$WinStartUp = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$StartupBat = Join-Path $WinStartUp "bginfo.bat"
Set-Content -Path $StartupBat -Value "@echo off`r`n`"$($bgInfoExe.FullName)`" `"$BgInfoDir\BGinfo.bgi`" /silent /timer:0 /nolicprompt"

& $bgInfoExe.FullName "$BgInfoDir\BGinfo.bgi" /silent /timer:0 /nolicprompt
