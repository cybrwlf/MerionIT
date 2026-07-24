#Requires -RunAsAdministrator
<#
Dell OEM images tend to preinstall Office/OneNote with several language packs at once. This tries
a targeted removal (Office Deployment Tool "Remove" config, keeping only the requested language)
first. If that doesn't fully clear the extra languages, it falls back to a full Office removal via
Microsoft's SaRA tool and a clean English-only reinstall via winget.

NOTE: this has not yet been tested against a real Dell OEM image - verify the targeted-removal path
actually works before relying on it as the default. See brainstorms/2026-07-23-merionit-onboarding-github-repo.md, Q14.

Sources consulted: learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options,
office365itpros.com/2018/10/15/office-clicktorun-registry, thewindowsclub.com (SaRAcmd.exe switches).
#>
param(
    [string[]]$KeepLanguage = @("en-us"),
    [string]$ProductId = "O365ProPlusRetail"
)

$OdtDir = "C:\MerionIT\ODT"
New-Item -ItemType Directory -Path $OdtDir -Force | Out-Null

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

$installedLangs = @($config.ClientCulture -split ',' | Where-Object { $_ })
$langsToRemove = @($installedLangs | Where-Object { $KeepLanguage -notcontains $_ })

if (-not $langsToRemove) {
    Write-Host "No extra language packs detected beyond $($KeepLanguage -join ', ') - nothing to do."
    return
}

Write-Host "Installing Office Deployment Tool via winget..."
winget install --id Microsoft.OfficeDeploymentTool --silent --accept-package-agreements --accept-source-agreements --location $OdtDir

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
Start-Sleep -Seconds 5

$stillInstalled = @((Get-ItemProperty -Path $c2rKey -ErrorAction SilentlyContinue).ClientCulture -split ',' | Where-Object { $_ })
$remaining = @($stillInstalled | Where-Object { $KeepLanguage -notcontains $_ })

if ($remaining) {
    Write-Warning "Targeted removal did not fully clear extra languages ($($remaining -join ', ')). Falling back to full removal + clean reinstall."

    $saraZip = Join-Path $OdtDir "SaRACmd.zip"
    Invoke-WebRequest -Uri "https://aka.ms/SaRA_EnterpriseVersionFiles" -OutFile $saraZip
    Expand-Archive -Path $saraZip -DestinationPath (Join-Path $OdtDir "SaRA") -Force
    $saraCmd = Get-ChildItem -Path (Join-Path $OdtDir "SaRA") -Filter "SaRAcmd.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($saraCmd) {
        & $saraCmd.FullName -S OfficeScrubScenario -AcceptEula -OfficeVersion All
        Write-Host "Reinstalling Office, English only..."
        winget install --id Microsoft.Office --silent --accept-package-agreements --accept-source-agreements --locale en-us
    } else {
        Write-Error "Could not find SaRAcmd.exe - do the full removal manually via https://aka.ms/SaRA_OfficeUninstall, then reinstall Office (English only)."
    }
} else {
    Write-Host "Extra language packs removed successfully - only $($KeepLanguage -join ', ') remain."
}
