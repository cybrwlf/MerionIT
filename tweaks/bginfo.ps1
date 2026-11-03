<#
Displays system info on the desktop background via Sysinternals BGInfo. Installs BGInfo via
winget instead of vendoring the .exe (the old process shipped a local BGinfo/ folder with the
binary in it - this fetches it from Microsoft instead). Uses the .bgi config committed alongside
this script (bginfo.bgi). A light-theme variant (bginfo-white.bgi) was never actually wired up
to anything - archived at archive/bginfo-white.bgi if that's wanted later
(pass -ConfigFile "$PSScriptRoot\..\archive\bginfo-white.bgi" to use it).

-AllowHashMismatch: if winget refuses the install with "Installer hash does not match", retry once with
winget's hash check overridden. Off by default, because that check is what protects the machine from a
bad installer. The override setting is switched back off afterwards.
-SkipInstall: never call winget. Uses the BGInfo already in C:\BGinfo, and stops if there isn't one.

If winget is missing or doesn't produce Bginfo*.exe, falls back to downloading BGInfo.zip straight from
download.sysinternals.com. That copy is only used if every .exe in it carries a valid Microsoft
Authenticode signature: the package hash can go stale, the signature can't.
#>
param(
    [string]$ConfigFile = "$PSScriptRoot\bginfo.bgi",
    [switch]$AllowHashMismatch,
    [switch]$SkipInstall
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "bginfo.ps1 needs an elevated PowerShell (Run as administrator). C:\BGinfo is writable by Administrators and SYSTEM only. Nothing was changed."
    return
}

Get-NetAdapterBinding | Where-Object ComponentID -EQ 'ms_tcpip6' | Disable-NetAdapterBinding -ComponentID 'ms_tcpip6'

$BgInfoDir = "C:\BGinfo"

# Only call winget when BGInfo isn't already in the folder. winget re-downloads and hash-checks the
# package every run, and Microsoft's package hash has drifted from the live download before ("Installer
# hash does not match"). The hash check stays on; an existing copy just doesn't need it.
$bgInfoExe = Get-ChildItem -Path $BgInfoDir -Filter "Bginfo*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bgInfoExe -and $SkipInstall) {
    Write-Warning "-SkipInstall was given and there is no Bginfo*.exe in $BgInfoDir. BGInfo was not set up."
    return
}
# Fallback when winget can't deliver BGInfo. Seen 2026-11-02 on MIP3004-LT601: winget's manifest was
# 4.33 while download.sysinternals.com already served 4.34 at the same URL, so winget failed with
# "Installer hash does not match" (and refuses the override when run as admin). Everything in the zip
# is staged in TEMP and only copied into $Dir if every .exe is validly signed by Microsoft.
function Install-BgInfoDirect {
    param([string]$Dir)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $zip = Join-Path $env:TEMP "BGInfo-$(Get-Random).zip"
    $stage = Join-Path $env:TEMP "BGInfo-stage-$(Get-Random)"
    try {
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/BGInfo.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $zip -DestinationPath $stage -Force -ErrorAction Stop
        $exes = @(Get-ChildItem -Path $stage -Filter '*.exe' -Recurse)
        if (-not $exes) {
            Write-Warning "BGInfo.zip had no .exe in it. Not installed."
            return
        }
        foreach ($exe in $exes) {
            $sig = Get-AuthenticodeSignature -FilePath $exe.FullName
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
                Write-Warning "$($exe.Name) failed the signature check (status: $($sig.Status), signer: $($sig.SignerCertificate.Subject)). Not installed."
                return
            }
            Write-Host "$($exe.Name): signature valid ($($sig.SignerCertificate.Subject))"
        }
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        Copy-Item -Path "$stage\*" -Destination $Dir -Recurse -Force
    } catch {
        Write-Warning "Direct BGInfo download failed: $($_.Exception.Message)"
    } finally {
        Remove-Item -Path $zip, $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $bgInfoExe) {
    New-Item -ItemType Directory -Path $BgInfoDir -Force | Out-Null
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetOut = winget install --id Microsoft.Sysinternals.BGInfo --source winget --silent --accept-package-agreements --accept-source-agreements --location $BgInfoDir 2>&1 | Out-String
        Write-Host $wingetOut
        $bgInfoExe = Get-ChildItem -Path $BgInfoDir -Filter "Bginfo*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $bgInfoExe -and $AllowHashMismatch -and $wingetOut -match 'hash does not match') {
            # --ignore-security-hash only works while winget's InstallerHashOverride setting is on (admin only).
            # Turn it on for this one install and always turn it back off.
            Write-Warning "winget says the installer hash does not match. -AllowHashMismatch was given, so retrying with winget's hash check overridden."
            winget settings --enable InstallerHashOverride | Out-Null
            try {
                winget install --id Microsoft.Sysinternals.BGInfo --source winget --silent --accept-package-agreements --accept-source-agreements --ignore-security-hash --location $BgInfoDir
            } finally {
                winget settings --disable InstallerHashOverride | Out-Null
            }
            $bgInfoExe = Get-ChildItem -Path $BgInfoDir -Filter "Bginfo*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    } else {
        Write-Warning "winget not available."
    }
    if (-not $bgInfoExe) {
        Write-Warning "winget did not install BGInfo - falling back to the signed download from download.sysinternals.com."
        Install-BgInfoDirect -Dir $BgInfoDir
        $bgInfoExe = Get-ChildItem -Path $BgInfoDir -Filter "Bginfo*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
}
if (-not $bgInfoExe) {
    Write-Error "BGInfo executable not found after winget and the direct download. Install it manually from https://learn.microsoft.com/sysinternals/downloads/bginfo"
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

# BGInfo second pass. On a brand-new profile's first sign-in Windows finishes its own first-run work
# (taskbar layout, wallpaper) a few seconds AFTER the startup entry has run BGInfo, and that wipes the
# background BGInfo just drew. Seen 2026-10-16: BGInfo wrote its image, Windows rewrote the wallpaper
# 42 ms later and the wallpaper setting ended up empty. A second run 90 seconds after every logon draws it
# again once things have settled. Runs as whoever signed in (Users group), hidden, no prompt.
$bgTaskName = 'MerionIT BGInfo second pass'
$bgAction = New-ScheduledTaskAction -Execute $bgInfoExe.FullName -Argument "`"$BgInfoDir\BGinfo.bgi`" /silent /timer:0 /nolicprompt"
$bgTrigger = New-ScheduledTaskTrigger -AtLogOn
$bgTrigger.Delay = 'PT90S'
$bgPrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
$bgSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $bgTaskName -Action $bgAction -Trigger $bgTrigger -Principal $bgPrincipal -Settings $bgSettings -Description 'Re-draws BGInfo 90 s after logon, after Windows first-run work on a new profile has finished.' -Force | Out-Null

& $bgInfoExe.FullName "$BgInfoDir\BGinfo.bgi" /silent /timer:0 /nolicprompt
