#Requires -RunAsAdministrator
<#
Dell OEM images tend to preinstall Office/OneNote with several language packs at once. This tries
a targeted removal (Office Deployment Tool "Remove" config, keeping only the requested language)
first. If that doesn't fully clear the extra languages, it falls back to a full Office removal via
Microsoft's SaRA tool and a clean English-only reinstall via winget.

Tested against a real Dell OEM image 2026-07-27: the initial detection (ClientCulture-based) missed
real installed language packs entirely, fixed by scanning the Uninstall registry instead (see
comment below). Same test also caught two more real bugs: the ODT removal was only given 5 seconds
before being checked (Click-to-Run applies it in the background - can take a couple minutes, so the
check ran too early and falsely looked like it failed) and the SaRA fallback tool's real executable
is GetHelpCmd.exe, not SaRAcmd.exe (Microsoft renamed it). Both fixed. Still unconfirmed: whether the
ODT targeted-removal actually clears the packs once given enough time - that needs a re-test.
See brainstorms/2026-07-23-merionit-onboarding-github-repo.md, Q14.

Sources consulted: learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options,
office365itpros.com/2018/10/15/office-clicktorun-registry.

Full console output is transcribed to C:\MerionIT\logs\Fix-OfficeLanguages-<timestamp>.log.
#>
param(
    [string[]]$KeepLanguage = @("en-us"),
    [string]$ProductId = "O365ProPlusRetail"
)

$OdtDir = "C:\MerionIT\ODT"
New-Item -ItemType Directory -Path $OdtDir -Force | Out-Null

$LogDir = "C:\MerionIT\logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "Fix-OfficeLanguages-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log") | Out-Null

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is required to fetch the Office Deployment Tool. Aborting."
    return
}

$c2rKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
$config = Get-ItemProperty -Path $c2rKey -ErrorAction SilentlyContinue
if (-not $config) {
    Write-Host "No Click-to-Run Office installation detected - nothing to do."
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
    return
}

Write-Host "Installing Office Deployment Tool via winget..."
winget install --id Microsoft.OfficeDeploymentTool --source winget --silent --accept-package-agreements --accept-source-agreements --location $OdtDir

$setupExe = Get-ChildItem -Path $OdtDir -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
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
        # waiting here, the winget reinstall below ran while Office was still mid-uninstall and
        # failed with "No applicable installer found," leaving the machine with no Office at all.
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

        Write-Host "Reinstalling Office, English only..."
        winget install --id Microsoft.Office --source winget --silent --accept-package-agreements --accept-source-agreements --locale en-us
    } else {
        Write-Error "Could not find GetHelpCmd.exe - do the full removal manually via https://aka.ms/SaRA_OfficeUninstall, then reinstall Office (English only)."
    }
} else {
    Write-Host "Extra language packs removed successfully - only $($KeepLanguage -join ', ') remain."
}

Stop-Transcript | Out-Null
