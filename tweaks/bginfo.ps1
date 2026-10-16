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

# winget leaves Bginfo.exe with an ACL that names only the account that ran setup, Administrators
# and SYSTEM, and C:\ hands Authenticated Users Modify to everything else. A local admin runs with a
# filtered token at logon, so it cannot start Bginfo.exe: the startup bat then fails silently for
# every user except the setup account (seen 2026-10-15 on a test machine: a newly added local admin never got the
# background). Meanwhile any signed-in user could edit the .bgi that runs at everyone's logon.
# Set it explicitly: SYSTEM and Administrators full control, Users read and execute, nothing else.
# SIDs rather than names so it works on any language build. Grant on the folder, drop the folder's
# inheritance, then reset every file under it to inherit from the folder. Do not use /T on the
# grant: tested, it left the .bgi with an empty ACL and never gave Bginfo.exe the Users entry.
& icacls.exe $BgInfoDir /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
& icacls.exe $BgInfoDir /inheritance:r | Out-Null
& icacls.exe "$BgInfoDir\*" /reset /T /C | Out-Null
$usersCanRun = (Get-Acl $bgInfoExe.FullName).Access | Where-Object {
    $_.AccessControlType -eq 'Allow' -and
    $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-545' -and
    ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ExecuteFile)
}
if (-not $usersCanRun) {
    Write-Warning "Users still cannot run $($bgInfoExe.FullName). BGInfo will only start for accounts named in its ACL."
}

$WinStartUp = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$StartupBat = Join-Path $WinStartUp "bginfo.bat"
Set-Content -Path $StartupBat -Value "@echo off`r`n`"$($bgInfoExe.FullName)`" `"$BgInfoDir\BGinfo.bgi`" /silent /timer:0 /nolicprompt"

& $bgInfoExe.FullName "$BgInfoDir\BGinfo.bgi" /silent /timer:0 /nolicprompt
