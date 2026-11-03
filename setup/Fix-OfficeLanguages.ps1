#Requires -RunAsAdministrator
<#
Dell OEM images tend to preinstall Office/OneNote with several language packs at once. This tries
a targeted removal (Office Deployment Tool "Remove" config, keeping only the requested language)
first. If that doesn't fully clear the extra languages, it falls back to a full Office removal via
Microsoft's SaRA tool and a clean English-only reinstall via ODT. Also handles the case where Office
isn't installed at all (including a machine this same script previously scrubbed) by installing it
fresh - the job here is "only en-us Office ends up on this machine," not just "trim languages if
Office happens to already be there."

Tested against a real Dell OEM image 2026-07-27, several rounds of real bugs found and fixed:
- Detection was ClientCulture-based and missed real installed language packs entirely - fixed by
  scanning the Uninstall registry instead (see comment below).
- The ODT removal was only given 5 seconds before being checked - Click-to-Run applies it in the
  background and can take a couple minutes, so the check ran too early and falsely looked like it
  failed. Now polls for up to 3 minutes.
- The SaRA fallback tool's real executable is GetHelpCmd.exe, not SaRAcmd.exe (Microsoft renamed
  it), and its -OfficeVersion flag is gone.
- GetHelpCmd's uninstall runs in the background too and was not waited for, so the reinstall that
  followed ran while Office was still mid-uninstall and failed, leaving the machine with no Office
  at all. Now polls for up to 5 minutes before reinstalling.
- The reinstall itself used `winget install --id Microsoft.Office --locale en-us`, but that
  package's silent-install switch is hardcoded by Microsoft to `/configure
  https://aka.ms/fhlwingetconfig` - winget's own generic config, completely ignoring our --locale
  flag (confirmed directly against the winget-pkgs manifest). It returned instantly with no output
  and installed nothing. Replaced with an ODT "Add" config we control, same tool already used for
  removal.
- 2026-11-03 (MIP3004-LT601): "is Office installed" only checked that the ClickToRun\Configuration
  key existed. A scrub left the key behind empty, so the script said "nothing to do" with no Office
  on the machine. Now it needs a product listed and WINWORD.EXE on disk, checks the same after every
  install, and adds a reminder line if Office still isn't there.

Still unconfirmed: whether the ODT targeted-removal path actually clears extra languages once given
enough time (vs. always falling back to the full scrub) - needs a re-test.
See brainstorms/2026-07-23-merionit-onboarding-github-repo.md, Q14.

Sources consulted: learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options,
office365itpros.com/2018/10/15/office-clicktorun-registry.

Full console output is transcribed to C:\MerionIT\logs\Fix-OfficeLanguages-<timestamp>.log.
#>
param(
    [string[]]$KeepLanguage = @("en-us"),
    [string]$ProductId = "O365ProPlusRetail",
    # Do nothing at all. This script can install Office (several GB) or strip and reinstall it, so on
    # slow internet it is skipped whole rather than half-run. Run it again later without this.
    [switch]$SkipInstall,
    # Retry the Office Deployment Tool download with winget's hash check overridden if winget says
    # "Installer hash does not match". Off by default.
    [switch]$AllowHashMismatch
)

if ($SkipInstall) {
    Write-Host "-SkipInstall: skipping the Office language fix and any Office install. Run Fix-OfficeLanguages.ps1 again later without it."
    return
}

$OdtDir = "C:\MerionIT\ODT"
New-Item -ItemType Directory -Path $OdtDir -Force | Out-Null

$LogDir = "C:\MerionIT\logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "Fix-OfficeLanguages-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log") | Out-Null

# Do nothing when the person signed in is a standard user. Setup can be started by a standard user who
# types an admin account's credentials at the UAC prompt: the process is elevated, so #Requires above is
# satisfied, but this script's fallback does a full Office scrub (SaRA) and then needs a working
# reinstall. Found in the field 2026-10-13: it removed Office completely, and a standard user could not
# put it back. Nobody signed in (Kaseya/SYSTEM) is fine and carries on as before.
# If the signed-in user cannot be proven to be a local administrator, it skips. Skipping is the safe
# direction: the machine keeps whatever Office it has, and this can be re-run later by an admin.
function Get-InteractiveUserCheck {
    $console = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    if (-not $console) { return [pscustomobject]@{ Ok = $true; Why = "no interactive user signed in" } }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($console -ieq $me) { return [pscustomobject]@{ Ok = $true; Why = "running as the signed-in user ($console), who is elevated" } }
    try {
        $sid = ([Security.Principal.NTAccount]$console).Translate([Security.Principal.SecurityIdentifier]).Value
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | ForEach-Object { $_.SID.Value })
    } catch {
        return [pscustomobject]@{ Ok = $false; Why = "could not confirm whether signed-in user '$console' is an administrator ($($_.Exception.Message))" }
    }
    if ($admins -contains $sid) { return [pscustomobject]@{ Ok = $true; Why = "signed-in user '$console' is a local administrator" } }
    return [pscustomobject]@{ Ok = $false; Why = "signed-in user '$console' is not a local administrator" }
}
$userCheck = Get-InteractiveUserCheck
if (-not $userCheck.Ok) {
    Write-Warning "SKIPPING Office language fix: $($userCheck.Why)."
    Write-Warning "Office was NOT touched. Run setup\Fix-OfficeLanguages.ps1 later while signed in as an administrator."
    Stop-Transcript | Out-Null
    return
}
Write-Host "Office language fix: proceeding ($($userCheck.Why))."

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is required to fetch the Office Deployment Tool. Aborting."
    return
}

$ReminderPath = "C:\MerionIT\setup\Manual-Steps-Reminder.txt"
function Add-ReminderIfMissing {
    # Inserts before the closing "====" banner line so dynamic reminders land inside the
    # checklist box instead of trailing after it.
    param([string]$Line)
    if (-not (Test-Path $ReminderPath)) { return }
    if (Select-String -Path $ReminderPath -Pattern ([regex]::Escape($Line)) -Quiet) { return }
    $content = @(Get-Content -Path $ReminderPath)
    if ($content.Count -gt 0 -and $content[-1] -match '^=+$') {
        $newContent = $content[0..($content.Count - 2)] + $Line + $content[-1]
    } else {
        $newContent = $content + $Line
    }
    Set-Content -Path $ReminderPath -Value $newContent
}

$c2rKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
# Office counts as installed only if Click-to-Run lists a product AND Word is on disk. Found on
# MIP3004-LT601 2026-11-03: a GetHelpCmd scrub left an empty ClickToRun\Configuration key behind,
# so the old "key exists" check said Office was there and the reinstall was skipped.
function Test-OfficeInstalled {
    $cfg = Get-ItemProperty -Path $c2rKey -ErrorAction SilentlyContinue
    if (-not $cfg -or -not $cfg.ProductReleaseIds) { return $false }
    $root = if ($cfg.InstallationPath) { $cfg.InstallationPath } else { "$env:ProgramFiles\Microsoft Office" }
    return (Test-Path (Join-Path $root "root\Office16\WINWORD.EXE"))
}

function Get-OdtSetupExe {
    param([string]$OdtDir)
    $exe = Get-ChildItem -Path $OdtDir -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { return $exe }
    Write-Host "Installing Office Deployment Tool via winget..."
    $wingetOut = winget install --id Microsoft.OfficeDeploymentTool --source winget --silent --accept-package-agreements --accept-source-agreements --location $OdtDir 2>&1 | Out-String
    Write-Host $wingetOut
    if ($AllowHashMismatch -and $wingetOut -match 'hash does not match') {
        Write-Warning "winget says the installer hash does not match. -AllowHashMismatch was given, so retrying with winget's hash check overridden."
        winget settings --enable InstallerHashOverride | Out-Null
        try {
            winget install --id Microsoft.OfficeDeploymentTool --source winget --silent --accept-package-agreements --accept-source-agreements --ignore-security-hash --location $OdtDir
        } finally {
            winget settings --disable InstallerHashOverride | Out-Null
        }
    }
    return (Get-ChildItem -Path $OdtDir -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Install-OfficeEnglishOnly {
    <#
    Installs Office via ODT's own "Add" config instead of winget's Microsoft.Office package - that
    package's silent switch is hardcoded by Microsoft to its own online config and ignores any
    language flag we pass, confirmed against the real manifest 2026-07-27.
    #>
    param([string]$OdtDir, [string]$ProductId, [string]$Language)
    $setupExe = Get-OdtSetupExe -OdtDir $OdtDir
    if (-not $setupExe) {
        Write-Error "Could not find ODT setup.exe after install - install Office manually."
        Add-ReminderIfMissing "[ ] Office did not install - run C:\MerionIT\setup\Fix-OfficeLanguages.ps1 as an admin"
        return
    }
    $addConfig = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="$ProductId">
      <Language ID="$Language" />
    </Product>
  </Add>
</Configuration>
"@
    $addConfigPath = Join-Path $OdtDir "add-office.xml"
    Set-Content -Path $addConfigPath -Value $addConfig
    Write-Host "Installing Office ($Language only) via ODT..."
    & $setupExe.FullName /configure $addConfigPath
    # setup.exe /configure blocks until Click-to-Run finishes, so check the result right away.
    if (Test-OfficeInstalled) {
        Write-Host "Office installed: WINWORD.EXE found."
    } else {
        Write-Warning "ODT finished but Office is not installed (no product in Click-to-Run or no WINWORD.EXE)."
        Add-ReminderIfMissing "[ ] Office did not install - run C:\MerionIT\setup\Fix-OfficeLanguages.ps1 as an admin"
    }
}

if (-not (Test-OfficeInstalled)) {
    # No Office at all isn't automatically "nothing to do" - a previous run of this same script can
    # leave a machine in exactly this state (full scrub via GetHelpCmd, reinstall never completed).
    Write-Host "No Office installation detected - installing Office fresh..."
    Install-OfficeEnglishOnly -OdtDir $OdtDir -ProductId $ProductId -Language $KeepLanguage[0]
    Stop-Transcript | Out-Null
    return
}

# ClientCulture (the ClickToRun UI-culture value) only reflects the active display language, not
# every language pack actually installed alongside it - confirmed in the field 2026-07-27: a Dell
# OEM image showed es-es/fr-fr/pt-br packs in Programs and Features while ClientCulture reported
# only en-us. Each extra language pack shows up as its own "Microsoft 365 - xx-xx" entry in the
# Uninstall registry, so that's the reliable signal for what's actually installed.
$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$installedLangs = @(
    Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^Microsoft 365 - ([a-z]{2}-[a-z]{2})$' } |
        ForEach-Object { $matches[1] } |
        Select-Object -Unique
)
$langsToRemove = @($installedLangs | Where-Object { $KeepLanguage -notcontains $_ })

if (-not $langsToRemove) {
    Write-Host "No extra language packs detected beyond $($KeepLanguage -join ', ') - nothing to do."
    Stop-Transcript | Out-Null
    return
}

$setupExe = Get-OdtSetupExe -OdtDir $OdtDir
if (-not $setupExe) {
    Write-Error "Could not find ODT setup.exe after install - aborting targeted removal."
    return
}

$languageXml = ($langsToRemove | ForEach-Object { "      <Language ID=`"$_`" />" }) -join "`n"
$removeConfig = @"
<Configuration>
  <Remove>
    <Product ID="$ProductId">
$languageXml
    </Product>
  </Remove>
</Configuration>
"@
$removeConfigPath = Join-Path $OdtDir "remove-languages.xml"
Set-Content -Path $removeConfigPath -Value $removeConfig

Write-Host "Attempting targeted removal of: $($langsToRemove -join ', ')"
& $setupExe.FullName /configure $removeConfigPath

Write-Host "Waiting for Click-to-Run to apply the change (this runs in the background and can take a couple minutes)..."
$maxWaitSeconds = 180
$waited = 0
do {
    Start-Sleep -Seconds 15
    $waited += 15
    $stillInstalled = @(
        Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '^Microsoft 365 - ([a-z]{2}-[a-z]{2})$' } |
            ForEach-Object { $matches[1] } |
            Select-Object -Unique
    )
    $remaining = @($stillInstalled | Where-Object { $KeepLanguage -notcontains $_ })
} while ($remaining -and $waited -lt $maxWaitSeconds)

if ($remaining) {
    Write-Warning "Targeted removal did not fully clear extra languages ($($remaining -join ', ')). Falling back to full removal + clean reinstall."

    $saraZip = Join-Path $OdtDir "SaRACmd.zip"
    Invoke-WebRequest -Uri "https://aka.ms/SaRA_EnterpriseVersionFiles" -OutFile $saraZip
    Expand-Archive -Path $saraZip -DestinationPath (Join-Path $OdtDir "SaRA") -Force
    # Microsoft renamed this tool's executable from SaRAcmd.exe to GetHelpCmd.exe (same download
    # URL, same "SaRA" branding, different binary name) - confirmed against the real download
    # 2026-07-27. Its -OfficeVersion flag is also gone; -S OfficeScrubScenario -AcceptEula is all
    # it accepts now (confirmed via GetHelpCmd.exe /?).
    $saraCmd = Get-ChildItem -Path (Join-Path $OdtDir "SaRA") -Filter "GetHelpCmd.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($saraCmd) {
        & $saraCmd.FullName -S OfficeScrubScenario -AcceptEula

        # GetHelpCmd itself reports "Uninstall office is running in the background" - it does not
        # block until the uninstall actually finishes. Confirmed in the field 2026-07-27: without
        # waiting here, the reinstall below ran while Office was still mid-uninstall and failed,
        # leaving the machine with no Office at all.
        Write-Host "Waiting for the Office uninstall to actually finish..."
        $officeMaxWaitSeconds = 300
        $officeWaited = 0
        do {
            Start-Sleep -Seconds 15
            $officeWaited += 15
            $officeStillPresent = [bool](
                Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "Microsoft 365*" -or $_.DisplayName -like "Microsoft Office*" }
            )
        } while ($officeStillPresent -and $officeWaited -lt $officeMaxWaitSeconds)

        Install-OfficeEnglishOnly -OdtDir $OdtDir -ProductId $ProductId -Language $KeepLanguage[0]
    } else {
        Write-Error "Could not find GetHelpCmd.exe - do the full removal manually via https://aka.ms/SaRA_OfficeUninstall, then reinstall Office (English only)."
    }
} else {
    Write-Host "Extra language packs removed successfully - only $($KeepLanguage -join ', ') remain."
}

Stop-Transcript | Out-Null
