#Requires -RunAsAdministrator
<#
Installs/updates the standard app set. Runs automatically every time as part of 1st_Step.ps1 -
every machine should have this full set, so it always fires rather than being a manual menu choice.

Starts by making sure winget is actually ready to use: it's provisioned per-user by an
asynchronous Store process on first login, so it may not exist yet on a brand-new account
(pcsadmin is, per the documented process, the very first account ever logged into on a
freshly-reset machine) - see Wait-ForWinget below.

For each app: checks both `winget list` and `scoop list` (catches apps installed manually or via
either tool in a previous run - not just ones winget itself installed). If found via either,
updates through that same tool. If not found anywhere, installs via winget, falling back to
Scoop only for apps that actually have a real, official Scoop manifest (see ScoopId below - not
every app does, and a couple of previous entries here were guessed rather than verified against
ScoopInstaller/Extras directly, which was a mistake - fixed 2026-07-24).

Scoop itself gets installed with -RunAsAdmin (its installer otherwise refuses to run in an
elevated session, which this whole pipeline always is), in --global scope to
C:\ProgramData\scoop (so installed apps are usable by any account on the machine, not just
whichever admin ran setup), and with Git installed right after - Scoop requires Git to add/use
any bucket besides the built-in "main" one.

All winget/scoop command output is captured (never left to print directly to the console AND
leak into the pipeline) and logged to C:\MerionIT\InstallLog.csv in a Details column, so a
failure is actually diagnosable from the log afterward instead of a bare "failed" with no reason.

Zoom and Logitech Unifying are intentionally not included - both retired/no-longer-needed for Merion.
#>
param(
    [string]$LogPath = "C:\MerionIT\InstallLog.csv"
)

# ScoopId is $null where there's no real, official ScoopInstaller/Extras manifest for the app -
# confirmed directly against https://github.com/ScoopInstaller/Extras/tree/master/bucket on
# 2026-07-24 (adobe-reader and microsoft-teams do NOT exist there - a previous version of this
# script guessed those names without checking, which is exactly why they always failed).
$Apps = @(
    @{ Name = "Adobe Acrobat Reader"; WingetId = "Adobe.Acrobat.Reader.64-bit"; ScoopId = $null }
    @{ Name = "Google Chrome";        WingetId = "Google.Chrome";               ScoopId = "extras/googlechrome" }
    @{ Name = "7-Zip";                WingetId = "7zip.7zip";                   ScoopId = "7zip" }
    @{ Name = "Microsoft Teams";      WingetId = "Microsoft.Teams";             ScoopId = $null }
    # WingetId is $null here on purpose: winget's Famatech.AdvancedIPScanner package runs the
    # real vendor installer (Program Files, registry entries, the works). Scoop's manifest for
    # the same tool is portable instead - just downloads the archive and extracts it with a shim,
    # no real install - confirmed by reading the manifest directly. Since this is only needed
    # occasionally (not a daily-use app), portable is the better fit, so route it through Scoop
    # only and skip winget's real installer entirely.
    @{ Name = "Advanced IP Scanner";  WingetId = $null;                         ScoopId = "extras/advanced-ip-scanner" }
)

$ScoopGlobalDir = "C:\ProgramData\scoop"
$ScoopShimsDir = Join-Path $ScoopGlobalDir "shims"

function Test-WingetAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Wait-ForWinget {
    <#
    winget (via the App Installer package) is provisioned per-user by an asynchronous Store
    process on first login - it will not exist yet on a brand-new account (e.g. pcsadmin, which
    per the documented process is the very first account ever logged into on a freshly-reset
    machine) until that finishes. Force a re-register (fast, no download, works fine for a real
    user account - just not for SYSTEM) and give it a few seconds to catch up before falling
    back to Scoop for everything.
    #>
    if (Test-WingetAvailable) { return }

    Write-Warning "winget not found yet - this is normal on a brand-new account (e.g. pcsadmin's very first login). Attempting to register it..."
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" -ErrorAction Stop
    } catch {
        Write-Warning "Add-AppxPackage registration attempt failed: $($_.Exception.Message)"
    }

    $retries = 0
    while (-not (Test-WingetAvailable) -and $retries -lt 6) {
        Start-Sleep -Seconds 5
        $retries++
    }

    if (-not (Test-WingetAvailable)) {
        Write-Warning "winget still not available after waiting - every app below will fall back to Scoop where possible. If that's unexpected, install 'App Installer' from the Microsoft Store manually (archive/installwinget.ps1 has an old, unverified third-party fallback method if that doesn't work)."
    }
}

function Test-ScoopInstalled {
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return $true }
    return Test-Path (Join-Path $ScoopShimsDir "scoop.ps1")
}

function Install-Scoop {
    Write-Host "Scoop not found - installing it (admin + global scope)..."
    # Scoop's installer refuses to run elevated unless told to explicitly, and by default
    # installs per-user - neither works here: this whole pipeline runs elevated, and apps need
    # to be usable by whoever actually uses the machine (TempUser etc.), not just whichever
    # admin account ran setup.
    $env:SCOOP_GLOBAL = $ScoopGlobalDir
    $out = Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin -ScoopDir '$ScoopGlobalDir' -ScoopGlobalDir '$ScoopGlobalDir'" 2>&1 | Out-String

    # Scoop only updates the *current user's* PATH, even for a global install - make the shims
    # folder reachable machine-wide so every account can actually run what gets installed. This
    # needs real admin rights (not just "elevated enough for winget") - warn and continue rather
    # than fail the whole app run if it can't write HKLM for some reason.
    try {
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notlike "*$ScoopShimsDir*") {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$ScoopShimsDir", "Machine")
        }
    } catch {
        Write-Warning "Could not add Scoop's shims folder to the machine-wide PATH ($($_.Exception.Message)). Apps installed via Scoop may only be runnable by the account that installed them until this is fixed."
    }
    # Refresh this process's PATH so we can call `scoop`/`git` immediately without a new session.
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Scoop needs Git to add/use any bucket besides the built-in "main" one.
    $out += "`n--- installing git ---`n" + (& scoop install git 2>&1 | Out-String)
    return $out
}

function Test-GitAvailable {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Ensure-ScoopReady {
    <#
    Scoop needs Git for anything beyond the built-in "main" bucket, and (in current Scoop
    versions) even to update an already-installed app, since update checks for a newer Scoop
    release via Git first. Install-Scoop always installs Git right after bootstrapping Scoop
    itself - but if Scoop was already present on the machine from an earlier/manual setup, that
    bootstrap never runs, so Git can still be missing. Check for it independently every time.
    #>
    $output = ""
    if (-not (Test-ScoopInstalled)) {
        $output += Install-Scoop
    } elseif (-not (Test-GitAvailable)) {
        Write-Host "Scoop is installed but Git is missing - installing it..."
        $output += "`n--- installing git ---`n" + (& scoop install git 2>&1 | Out-String)
    }
    return $output
}

function Install-ViaScoop {
    param($App)
    $output = Ensure-ScoopReady
    if ($App.ScoopId -like "*/*") {
        $bucket = $App.ScoopId.Split('/')[0]
        $output += "`n--- adding bucket $bucket ---`n" + (& scoop bucket add $bucket 2>&1 | Out-String)
    }
    $output += "`n--- scoop install ---`n" + (& scoop install $App.ScoopId --global 2>&1 | Out-String)
    return $output
}

function Update-ViaScoop {
    param($App)
    $output = Ensure-ScoopReady
    $output += (& scoop update $App.ScoopId --global 2>&1 | Out-String)
    return $output
}

function Test-WingetAppInstalled {
    param($WingetId)
    $out = & winget list --id $WingetId --source winget --accept-source-agreements 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0) -and ($out -match [regex]::Escape($WingetId))
}

function Test-ScoopAppInstalled {
    param($ScoopId)
    if (-not $ScoopId -or -not (Test-ScoopInstalled)) { return $false }
    $bareName = $ScoopId.Split('/')[-1]
    $out = & scoop list $bareName 2>&1 | Out-String
    return ($out -match [regex]::Escape($bareName))
}

function Test-AlreadyPresentFromOutput {
    <#
    winget install can fail (non-zero exit) even when the app is genuinely already there - e.g.
    it was installed by some means winget's own upgrade-matching recognizes but our
    Test-WingetAppInstalled pre-check didn't catch. Rather than treat that as a real failure and
    trigger an unnecessary Scoop install alongside an app that's already present (this happened
    with Google Chrome in testing - installed a redundant second copy via Scoop), check winget's
    own message for the standard "nothing to do" phrasing first.
    #>
    param($Output)
    return ($Output -match "No available upgrade found" -or $Output -match "already installed")
}

function Test-AdobeAcrobatConflict {
    <#
    Adobe's Reader installer refuses to run at all if full Adobe Acrobat is already installed
    (a real, deliberate Adobe product conflict, not a bug) - confirmed via the installer's own
    log during testing: "The Installer requires that you uninstall Adobe Acrobat (64-bit) before
    continuing this installation, in order to avoid application conflict." Acrobat already
    covers everything Reader does, so this is correctly a skip, not a failure.
    #>
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $found = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "Adobe Acrobat*" -and $_.DisplayName -notlike "*Reader*" }
    return [bool]$found
}

Wait-ForWinget

$results = foreach ($app in $Apps) {
    $method = $null
    $uninstallCmd = $null
    $success = $false
    $details = ""

    if ($app.WingetId -eq "Adobe.Acrobat.Reader.64-bit" -and (Test-AdobeAcrobatConflict)) {
        Write-Host "Full Adobe Acrobat is already installed - it covers everything Reader does, skipping."
        $success = $true
        $method = "skipped (Adobe Acrobat already installed - Reader would conflict)"
        $uninstallCmd = "n/a"
        $details = "Adobe's installer refuses to install Reader alongside full Acrobat (product conflict, by Adobe's own design) - Acrobat already provides PDF viewing, so this is intentionally skipped, not a failure."
    } elseif (-not $app.WingetId) {
        # Scoop-only/portable app - no real installer involved at all (see the comment on this
        # app's entry above for why).
        if (Test-ScoopAppInstalled -ScoopId $app.ScoopId) {
            Write-Host "$($app.Name) already installed (scoop) - checking for updates..."
            $details = Update-ViaScoop -App $app
            $success = $true
            $method = "scoop --global (already installed)"
            $uninstallCmd = "scoop uninstall $($app.ScoopId) --global"
        } else {
            Write-Host "Installing $($app.Name) via Scoop (portable, no real install)..."
            $details = Install-ViaScoop -App $app
            if ($LASTEXITCODE -eq 0) {
                $success = $true
                $method = "scoop --global (portable)"
                $uninstallCmd = "scoop uninstall $($app.ScoopId) --global"
            }
        }
    } elseif (Test-WingetAppInstalled -WingetId $app.WingetId) {
        Write-Host "$($app.Name) already installed (winget) - checking for updates..."
        $details = & winget upgrade --id $app.WingetId --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
        # A non-zero exit here usually just means "no update available" - the app being present
        # at all is success for our purposes.
        $success = $true
        $method = "winget (already installed)"
        $uninstallCmd = "winget uninstall --id $($app.WingetId)"
    } elseif (Test-ScoopAppInstalled -ScoopId $app.ScoopId) {
        Write-Host "$($app.Name) already installed (scoop) - checking for updates..."
        $details = Update-ViaScoop -App $app
        $success = $true
        $method = "scoop --global (already installed)"
        $uninstallCmd = "scoop uninstall $($app.ScoopId) --global"
    } else {
        Write-Host "Installing $($app.Name) via winget..."
        $details = & winget install --id $app.WingetId --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $success = $true
            $method = "winget"
            $uninstallCmd = "winget uninstall --id $($app.WingetId)"
        } elseif (Test-AlreadyPresentFromOutput -Output $details) {
            Write-Host "$($app.Name) is already present per winget's own message - not a real failure, skipping Scoop."
            $success = $true
            $method = "winget (already installed - detected from install output)"
            $uninstallCmd = "winget uninstall --id $($app.WingetId)"
        } elseif ($app.ScoopId) {
            Write-Warning "$($app.Name) failed via winget - trying Scoop..."
            $scoopDetails = Install-ViaScoop -App $app
            $details += "`n--- Scoop fallback ---`n" + $scoopDetails
            if ($LASTEXITCODE -eq 0) {
                $success = $true
                $method = "scoop --global"
                $uninstallCmd = "scoop uninstall $($app.ScoopId) --global"
            }
        }
    }

    if (-not $success) {
        $viaText = if (-not $app.WingetId) { "Scoop" } elseif ($app.ScoopId) { "winget or Scoop" } else { "winget (no verified Scoop manifest exists for this app - see comments at the top of this script)" }
        Write-Warning "Failed to install $($app.Name) via $viaText - install it manually. See the Details column in $LogPath for why."
        $method = "FAILED"
        $uninstallCmd = "n/a"
    }

    [PSCustomObject]@{
        App       = $app.Name
        Method    = $method
        Uninstall = $uninstallCmd
        Details   = ($details -replace "\s+", " ").Trim()
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

$results | Export-Csv -Path $LogPath -NoTypeInformation -Append
Write-Host "Install log written to $LogPath"
