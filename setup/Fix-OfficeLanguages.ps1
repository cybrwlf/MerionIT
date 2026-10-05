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

Still unconfirmed: whether the ODT targeted-removal path actually clears extra languages once given
enough time (vs. always falling back to the full scrub) - needs a re-test.
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

function Get-OdtSetupExe {
    param([string]$OdtDir)
    $exe = Get-ChildItem -Path $OdtDir -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { return $exe }
    Write-Host "Installing Office Deployment Tool via winget..."
    winget install --id Microsoft.OfficeDeploymentTool --source winget --silent --accept-package-agreements --accept-source-agreements --location $OdtDir
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
}

$c2rKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
$config = Get-ItemProperty -Path $c2rKey -ErrorAction SilentlyContinue
if (-not $config) {
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
