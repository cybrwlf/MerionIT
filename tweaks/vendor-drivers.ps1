<#
Vendor-specific driver handling.

Merion buys Dell, but acquired properties arrive with whatever they had, so this branches on the
manufacturer rather than assuming.

  Dell           remove Dell Optimizer, Purchased Apps and SupportAssist, install Dell Command
                 Update, tame it, run it. Dell Trusted Device is kept on purpose.
  anything else  no-op - Windows Update already handles drivers, configured in basic10-11stuff.ps1

That is not a cop-out for the non-Dell case. Verified on MRM8065-DT201 2026-09-22: with the WU
policy this toolkit now sets, a plain Windows Update scan found and installed 8 driver and
firmware packages (Dell BIOS, two Intel chipset, Intel graphics extension) with no vendor tooling
involved at all. WU is a working driver path, just not an exhaustive one.

WHY NOT A VENDOR TOOL FOR LENOVO / HP:

  Lenovo was evaluated in full on 2026-09-22 (ThinkPad T14, see MerionIT-Lenovo-Baseline.md).
  Lenovo forces a choice Dell does not:
    - System Update (TVSU) pulls direct from Lenovo but is GUI-bound. Its documented /CM
      command-line mode still launches a window into the interactive session and waits: observed
      40 minutes elapsed, 0.9 seconds of CPU, window confirmed on screen. Cannot be automated.
    - Thin Installer is genuinely headless and leaves zero footprint, but per Lenovo's own readme
      it "searches for the update packages from a repository that you create". No hosted catalog.
      That means Update Retriever plus a maintained share, which conflicts with the island model -
      a divested property must not depend on a share it can no longer reach.
  Decision: Lenovo machines use Windows Update, and TVSU is run by hand at provisioning if wanted,
  since that is the one moment a technician is already at the keyboard.

  HP has not been evaluated. HP Image Assistant is the likely equivalent. Until someone tests it,
  HP falls through to Windows Update, which is a working answer rather than a guess.

WHAT DELL COSTS YOU, so this is a decision and not a surprise:

  DCU 5.7.2 silently installs "Dell Core Services", which leaves ~5 background processes running
  (Dell.TechHub, CoreServices.Client, Analytics/DataManager/Instrumentation SubAgents, and
  MyDell's Dell.UCA.Manager). Removing Core Services breaks dcu-cli outright - verified, it dies
  with "An unexpected fatal error occurred", return code 2. The agents cannot be disabled via the
  registry either: setting StartupType=0 on their AgentRegistration keys persists but is ignored,
  and they start anyway.

  What IS achievable, and is what this script does: no scheduled tasks, no toast notifications,
  nothing user-visible, nothing self-initiated. The interruptions are gone; the background
  processes are not. Telemetry consent flags are set to 0.

  Worth it because DCU finds things nothing else does. On MRM8065-DT201 it flagged an Urgent
  Realtek driver that Windows Update did not offer and that dell.com/support reported as already
  up to date.
#>

param(
    # Where to get the DCU installer when C:\MerionIT\apps has no copy, which is every machine
    # reached remotely rather than from the build USB. There is no default on purpose: dl.dell.com
    # 403s scripted requests and Dell's driver pages 403/404 them too, so a working URL cannot be
    # derived at runtime and guessing one would be worse than asking. Point this at wherever Merion
    # hosts the installer.
    [string]$DcuInstallerUrl,

    # Expected SHA-256 of whatever $DcuInstallerUrl serves. The download is REFUSED if it does not
    # match, and refused if this is omitted. A 90 MB executable pulled over the network and run
    # elevated is exactly the thing that gets verified before it runs, not after.
    # 5.7.2 A00 (WYJ59): 5C20E1A352FDBC0A9759504DB37C7B8C694F4024F5F5313C5130C0959BE8D484
    [string]$DcuInstallerSha256,

    # Run `dcu-cli /applyUpdates` at the end, which applies driver AND firmware updates including
    # BIOS. OFF by default as of 2026-09-30. It used to be unconditional, which meant a fleet-wide
    # driver sweep also flashed BIOS on every Dell unattended. Installing and configuring DCU is a
    # safe thing to do everywhere; applying firmware is a decision per machine.
    [switch]$ApplyUpdates
)

Write-Host "======================================="
Write-Host "Vendor driver handling..."
Write-Host "======================================="

$ReminderPath = "C:\MerionIT\setup\Manual-Steps-Reminder.txt"
function Add-ReminderIfMissing {
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

$manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
$model        = (Get-CimInstance Win32_ComputerSystem).Model
Write-Host "  Manufacturer : $manufacturer"
Write-Host "  Model        : $model"

$wuPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

if ($manufacturer -notmatch 'Dell') {
    Write-Host "  Not a Dell - Windows Update handles drivers on this machine."
    Write-Host "  (WU policy is set by basic10-11stuff.ps1: 7-day quality deferral, feature"
    Write-Host "   updates unmanaged.)"
    # WU is the ONLY driver path here, so make sure nothing is suppressing driver offers -
    # e.g. a machine that carried the value over from an older image.
    if ((Get-ItemProperty $wuPolicy -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue)) {
        Remove-ItemProperty -Path $wuPolicy -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue
        Write-Host "  Cleared ExcludeWUDriversInQualityUpdate - WU must be free to offer drivers here."
    }
    Write-Host "======================================="
    return
}

# ---------------------------------------------------------------------------------
# Dell path
# ---------------------------------------------------------------------------------

# ORDER MATTERS, and it used to be wrong. SupportAssist was removed FIRST, then DCU installed.
# When the install failed the machine was left with neither - no nagware, but also no driver tooling
# at all. That happened for real on MRQ7582-LT301 on 2026-09-30: SupportAssist uninstalled cleanly,
# winget then failed 0x8A15000F, and the machine ended up worse than before the script ran.
#
# So DCU is installed and proven working first. SupportAssist removal is further down, and only
# runs once dcu-cli answers. A machine that keeps its nagware is a nuisance; a machine with no
# driver path is a problem.
# Script scope on purpose: both Remove-DellSupportAssist and the orphaned-Core-Services check
# below read it, and a copy inside the function would not be visible to the latter.
$uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'

# Uninstalls a program by its exact DisplayName, then checks the registry to see whether it really
# went. Returns $true only when no entry is left. The debloat scripts piped Get-Package into
# Uninstall-Package and printed "Successfully uninstalled" either way; Dell Optimizer survived every
# build like that (seen 2026-11-02 on MIP3004-LT601) because it is an InstallShield package whose
# UninstallString has no silent switch.
# Per entry, in order: QuietUninstallString (Burn bundles carry one), msiexec /x for MSIs, then
# UninstallString plus $SilentArgs. Exact names only, on purpose: Dell Command Update, Dell Core
# Services and Dell Trusted Device (kept, decided 2026-11-03) must never be caught by a wildcard.
function Remove-ProgramByName {
    param([string]$Name, [string]$SilentArgs, [int]$WaitSeconds = 600)
    $entries = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $Name })
    if (-not $entries) {
        Write-Host "    $Name : not installed"
        return $true
    }
    # Re-read after every uninstall: removing a bundle also removes the MSI entry it owns.
    for ($attempt = 1; $attempt -le 3 -and $entries; $attempt++) {
        $e = $entries | Where-Object QuietUninstallString | Select-Object -First 1
        if (-not $e) { $e = $entries[0] }
        if ($e.QuietUninstallString)     { $cmd = $e.QuietUninstallString }
        elseif ($e.WindowsInstaller -eq 1) { $cmd = "msiexec.exe /x $($e.PSChildName) /qn /norestart" }
        elseif ($SilentArgs)             { $cmd = "$($e.UninstallString) $SilentArgs" }
        else {
            Write-Warning "    $Name : no silent uninstall known for this entry - skipped."
            break
        }
        Write-Host "    $Name $($e.DisplayVersion): $cmd"
        $p = Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -WindowStyle Hidden -PassThru
        $null = $p.Handle  # PowerShell 5.1 reports no ExitCode later unless the handle is opened now
        if ($p.WaitForExit($WaitSeconds * 1000)) { Write-Host "    exit: $($p.ExitCode)" }
        else { Write-Warning "    uninstaller still running after $WaitSeconds s - not waiting any longer." }
        # InstallShield's -runfromtemp hands off to a copy of itself and returns at once, so the exit
        # code proves nothing. Poll for this entry's key to disappear instead.
        $waited = 0
        while ((Test-Path $e.PSPath) -and $waited -lt 180) { Start-Sleep -Seconds 10; $waited += 10 }
        $entries = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $Name })
        # The same entry surviving means this command doesn't work here. Running it again would only
        # stack up another hung uninstaller, so stop and let the reminder line take over.
        if (Test-Path $e.PSPath) { break }
    }
    if ($entries) {
        Write-Warning "    $Name : STILL INSTALLED"
        return $false
    }
    Write-Host "    $Name : removed (confirmed in the registry)"
    return $true
}

function Remove-DellSupportAssist {
Write-Host "  Removing Dell SupportAssist (the consumer nagware)..."
$saAppx = Get-AppxPackage -AllUsers -Name "*DellSupportAssist*" -ErrorAction SilentlyContinue
if ($saAppx) {
    # -AllUsers can fail 0x80070002 on a package whose files are already gone; the per-user
    # removal then succeeds. Try both rather than reporting a success we did not get.
    foreach ($p in $saAppx) {
        Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        Remove-AppxPackage -Package $p.PackageFullName -ErrorAction SilentlyContinue
    }
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*SupportAssist*" } |
        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
    $stillThere = Get-AppxPackage -AllUsers -Name "*DellSupportAssist*" -ErrorAction SilentlyContinue
    Write-Host "    appx: $(if ($stillThere) { 'STILL PRESENT' } else { 'removed' })"
}
# Remediation and the OS Recovery Plugin ship as Burn bundles beside the main MSI, and only the MSI
# used to be removed. Seen 2026-11-02 on MIP3004-LT601: both still installed, services running.
foreach ($n in 'Dell SupportAssist OS Recovery Plugin for Dell Update', 'Dell SupportAssist Remediation', 'Dell SupportAssist') {
    if (-not (Remove-ProgramByName -Name $n)) {
        Add-ReminderIfMissing "[ ] Uninstall $n (Settings > Apps) - silent uninstall didn't take"
    }
}
}

# --- Dell Command Update -----------------------------------------------------------
# DCU 5.7.0 Universal installs to Program Files (seen 2026-11-02 on MIP3004-LT601), older builds to
# Program Files (x86). Checking only x86 made a working DCU look absent: the script then removed
# Dell Core Services as "orphaned", gave up, and never reached the SupportAssist removal.
function Get-DcuCli {
    foreach ($root in $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
        $path = Join-Path $root 'Dell\CommandUpdate\dcu-cli.exe'
        if (Test-Path $path) { return $path }
    }
    return (Join-Path ${env:ProgramFiles(x86)} 'Dell\CommandUpdate\dcu-cli.exe')
}
$dcuCli = Get-DcuCli

if (-not (Test-Path $dcuCli)) {
    # DCU 5.7.2 requires .NET Desktop Runtime 10.0 >= 10.0.8. Its installer refuses without it,
    # so check before wasting time on an install that cannot succeed.
    $dotnetDir = Join-Path $env:ProgramFiles "dotnet\shared\Microsoft.WindowsDesktop.App"
    $haveDotnet = $false
    if (Test-Path $dotnetDir) {
        $haveDotnet = [bool](Get-ChildItem $dotnetDir -Directory -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -match '^10\.' -and [version]$_.Name -ge [version]'10.0.8' })
    }
    if (-not $haveDotnet) {
        Write-Warning "  .NET Desktop Runtime 10.0.8+ missing - DCU 5.7.2 will not install."
        Add-ReminderIfMissing "[ ] Install .NET Desktop Runtime 10.0.8+ then rerun tweaks\vendor-drivers.ps1 (Dell Command Update needs it)"
        Write-Host "======================================="
        return
    }

    # ---- orphaned Dell Core Services blocks the install -------------------------------------
    # The old debloat uninstalled Dell Command Update but left Dell Core Services behind. DCU 5.7.2
    # bundles Core Services 1.15.18.0 under a DIFFERENT ProductCode, so it is not a clean MSI major
    # upgrade: it tries to remove the old one, fails with 1603, rolls the whole thing back, and the
    # DUP reports DEP_HARD_ERROR / exit 4. The log line that gives it away is
    #     Product: Dell Core Services -- Installation operation failed ... error status: 1603
    #
    # Proven on MRQ7582-LT301 2026-09-30: with orphaned Core Services 1.0.248.0 present the install
    # failed exit 4 twice; removing it first made the same installer succeed exit 0, leaving
    # dcu-cli 5.7.2.7 and Core Services 1.15.18.0. Every Dell built on the old flow carries this.
    #
    # Only removed when DCU is absent. If dcu-cli exists we never reach here, so a working pair is
    # never touched.
    $orphan = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -eq 'Dell Core Services' } | Select-Object -First 1
    if ($orphan) {
        Write-Host "  Dell Core Services $($orphan.DisplayVersion) present without DCU - orphaned by the"
        Write-Host "  old debloat, and it will fail the DCU install (1603). Removing it first..."
        $p = Start-Process msiexec.exe -ArgumentList @('/x', $orphan.PSChildName, '/qn', '/norestart') -Wait -PassThru
        Write-Host "    uninstall exit: $($p.ExitCode)   (0 or 3010 = success)"
        Start-Sleep -Seconds 5
        $still = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -eq 'Dell Core Services' }
        if ($still) {
            Write-Warning "    Core Services still present - the DCU install will probably fail with exit 4."
        } else {
            Write-Host "    removed (DellTechHub and DellClientManagementService go with it; DCU reinstalls both)"
        }
    }

    # Staged on the USB rather than committed - the installer is ~86 MB. Downloading it here is
    # possible but dl.dell.com returns 403 to the default PowerShell user agent, and a freshly
    # imaged machine's network is not guaranteed.
    $installer = Get-ChildItem "C:\MerionIT\apps" -Filter "Dell-Command-Update*.EXE" -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
    if ($installer) {
        Write-Host "  Installing $($installer.Name) (silent, 5-7 min)..."
        $p = Start-Process $installer.FullName -ArgumentList @('/s') -Wait -PassThru
        Write-Host "    installer exit: $($p.ExitCode)"
        Start-Sleep -Seconds 10
    }
    elseif ($DcuInstallerUrl) {
        # Download + verify. Replaces the winget fallback, which was removed 2026-09-30 - see the
        # note below for why it could never have worked on the machines that need this most.
        Write-Host "  No installer in C:\MerionIT\apps - downloading..."
        $tmp = Join-Path $env:TEMP 'Dell-Command-Update-download.EXE'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            # dl.dell.com 403s the default PowerShell user agent, so send a browser one. Harmless
            # against any other host.
            Invoke-WebRequest $DcuInstallerUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop `
                -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36'
            Write-Host "    downloaded $('{0:N0}' -f (Get-Item $tmp).Length) bytes"

            $hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
            if (-not $DcuInstallerSha256) {
                Write-Warning "    REFUSING to run it: no -DcuInstallerSha256 given. Actual hash was $hash"
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
            elseif ($hash -ne $DcuInstallerSha256.Replace('-','').Trim().ToUpper()) {
                Write-Warning "    REFUSING to run it: SHA-256 mismatch."
                Write-Warning "      expected $($DcuInstallerSha256.ToUpper())"
                Write-Warning "      got      $hash"
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
            else {
                Write-Host "    SHA-256 matches"
                $sig = Get-AuthenticodeSignature $tmp
                Write-Host "    signature: $($sig.Status)  signer: $($sig.SignerCertificate.Subject)"
                if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Dell') {
                    Write-Warning "    REFUSING to run it: not a valid Dell signature."
                    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Host "  Installing (silent, 5-7 min)..."
                    $p = Start-Process $tmp -ArgumentList @('/s') -Wait -PassThru
                    Write-Host "    installer exit: $($p.ExitCode)"
                    Start-Sleep -Seconds 10
                    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Warning "  download failed: $($_.Exception.Message)"
        }
    }
    else {
        # winget was the fallback here until 2026-09-30. It was removed rather than fixed, because
        # it cannot work in the case it exists for. winget.exe is a PER-USER MSIX execution alias
        # living in %LOCALAPPDATA%\Microsoft\WindowsApps. There is no such path for SYSTEM, and
        # every remote run (Kaseya) is SYSTEM. It also failed 0x8A15000F on MRQ7582-LT301 when run
        # as a real elevated user, on a machine whose winget sources had not been touched since
        # 2023. Two independent reasons, so no amount of flag-tuning saves it.
        $isSystem = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value -eq 'S-1-5-18'
        Write-Warning "  No installer in C:\MerionIT\apps and no -DcuInstallerUrl given."
        Write-Host    "    Running as SYSTEM : $isSystem"
        Write-Host    "    Supply -DcuInstallerUrl and -DcuInstallerSha256, or stage the installer"
        Write-Host    "    into C:\MerionIT\apps first."
        Add-ReminderIfMissing "[ ] Dell Command Update not installed - no installer available. Stage it in C:\MerionIT\apps or pass -DcuInstallerUrl."
    }

    # Re-resolve: a fresh install may land in either Program Files folder.
    $dcuCli = Get-DcuCli
    if (-not (Test-Path $dcuCli)) {
        Write-Warning "  dcu-cli.exe still not present after install - giving up."
        Add-ReminderIfMissing "[ ] Dell Command Update install failed - install manually and rerun tweaks\vendor-drivers.ps1"
        Write-Host "======================================="
        return
    }
}
Write-Host "  dcu-cli: $((Get-Item $dcuCli).VersionInfo.ProductVersion)"

# DCU exists and this machine now has a driver path, so the nagware can go. Deliberately after the
# install, never before - see the note above Remove-DellSupportAssist.
#
# Dell Optimizer too, but only when Dell Core Services is installed. Seen 2026-11-03 on
# MIP3004-LT601: Core Services had been removed (the old x86-only path check made DCU look absent),
# so DCU 5.7.0 was running on the DellTechHub and DellClientManagementService that came with
# Optimizer's AppCore package. Removing Optimizer took AppCore, UserSubAgent and Purchased Apps with
# it, and dcu-cli then failed with exit 2 on everything until DCU was reinstalled. The health probe
# below catches a break either way.
Write-Host "  Removing Dell OEM extras..."
$coreServices = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq 'Dell Core Services' }
if ($coreServices) {
    # InstallShield, no QuietUninstallString: '-silent' is added to Dell's own '-remove -runfromtemp'.
    if (-not (Remove-ProgramByName -Name 'Dell Optimizer' -SilentArgs '-silent')) {
        Add-ReminderIfMissing "[ ] Uninstall Dell Optimizer (Settings > Apps) - silent uninstall didn't take"
    }
    # The successor to Dell Digital Delivery, which the debloat lists already target.
    if (-not (Remove-ProgramByName -Name 'Dell/Alienware Purchased Apps')) {
        Add-ReminderIfMissing "[ ] Uninstall Dell/Alienware Purchased Apps (Settings > Apps) - silent uninstall didn't take"
    }
} elseif (Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -in 'Dell Optimizer', 'Dell/Alienware Purchased Apps' }) {
    Write-Warning "  Dell Core Services is not installed - leaving Dell Optimizer in place, DCU may be running on its services."
    Add-ReminderIfMissing "[ ] Dell Optimizer left in place: Dell Core Services is missing. Reinstall DCU from C:\MerionIT\apps (brings Core Services), then rerun tweaks\vendor-drivers.ps1"
}
Remove-DellSupportAssist

# Health probe. Test-Path on dcu-cli.exe is NOT sufficient: a partial uninstall leaves the binary
# on disk while removing Dell Core Services, and every dcu-cli call then returns 2. The presence
# check above passes, the script proceeds, and all six /configure calls plus the scan fail.
# Observed on MRM8035-LT101 2026-09-23 after the debloat script had uninstalled DCU mid-run
# (see commit 82b7303) - dcu-cli.exe 5.7.2.7 present, every invocation exit 2.
& $dcuCli /configure -scheduleManual -silent 2>&1 | Out-Null
if ($LASTEXITCODE -eq 2) {
    # Exit 2 is usually NOT a missing install. Confirmed on MRM8035-LT101 2026-09-23: Dell Core
    # Services 1.14.151.0 was present and dcu-cli was 5.7.2.7, but DellClientManagementService -
    # the service dcu-cli actually drives - had been left Stopped/Disabled, and every call
    # returned 2. Re-enabling the service fixed it; a reinstall would have been wasted effort
    # (and `winget uninstall` failed with 1604 anyway).
    $svc = Get-Service DellClientManagementService -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Write-Host "  dcu-cli returned 2 - DellClientManagementService is $($svc.Status)/$($svc.StartType). Re-enabling..."
        Set-Service DellClientManagementService -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service DellClientManagementService -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        & $dcuCli /configure -scheduleManual -silent 2>&1 | Out-Null
        Write-Host "    retry exit: $LASTEXITCODE"
    }
}
if ($LASTEXITCODE -eq 2) {
    Write-Warning "  dcu-cli is present but non-functional (exit 2)."
    Write-Warning "  Check DellClientManagementService first; if that is running, reinstall DCU."
    Add-ReminderIfMissing "[ ] Dell Command Update is broken (dcu-cli exit 2) - check DellClientManagementService is Running, else reinstall DCU, then rerun tweaks\vendor-drivers.ps1"
    Write-Host "======================================="
    return
}

# --- DCU owns drivers on this machine, so stop Windows Update also offering them -------
# Deliberately AFTER the health probe: if dcu-cli were broken and we had already suppressed WU
# drivers, the machine would be left with no driver path at all.
#
# Why this is needed. Observed on MRM8035-LT101 2026-09-23: with WU free to offer drivers, it
# advertised 18 driver packages that could never install - seven superseded Intel graphics
# extensions (31.0.101.3959 through 32.0.101.6881, against 32.0.101.7088 installed), a Realtek
# package identical to what was already present, and HP printer drivers for devices whose PnP
# status was Unknown. Windows will not downgrade a driver or install one for absent hardware, so
# they sat in the pending list permanently while the UI kept asking for a restart that no
# pending-reboot flag agreed with. Rebooting cannot fix it; the update store is not corrupt.
#
# That machine had this value set before provisioning, and basic10-11stuff.ps1 deletes the whole
# WindowsUpdate key before writing its own values - which is what let the noise loose.
Write-Host "  Suppressing Windows Update driver offers (DCU owns drivers on Dell)..."
Set-ItemProperty -Path $wuPolicy -Name ExcludeWUDriversInQualityUpdate -Type DWord -Value 1 -ErrorAction SilentlyContinue
Restart-Service wuauserv -ErrorAction SilentlyContinue

# --- tame it ------------------------------------------------------------------------
# Applied one switch per call deliberately. Batched into a single call, DCU fails the whole lot
# with exit 109 "Invalid schedule action" - and -systemRestartDeferral=disable fails with 109 on
# its own regardless, so it is not in this list. With -scheduleManual there is no scheduled
# operation for a restart deferral to apply to anyway.
Write-Host "  Applying headless configuration..."
$dcuSettings = @(
    '-scheduleManual'                  # no automatic schedule - nothing self-initiates
    '-updatesNotification=disable'     # no toasts
    '-advancedDriverRestore=disable'
    '-autoSuspendBitLocker=enable'     # BIOS updates must not trip BitLocker recovery
    '-forceRestart=disable'
    '-delayDays=7'                     # mirrors the 7-day Windows Update quality deferral
)
foreach ($s in $dcuSettings) {
    & $dcuCli /configure $s -silent 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "    $s -> exit $LASTEXITCODE" } else { Write-Host "    $s" }
}

# --- run it -------------------------------------------------------------------------
# Exit codes that matter, confirmed live:
#   0   updates found and applied
#   500 no updates available - SUCCESS, not failure. A naive non-zero check reports a false
#       alarm on every healthy machine.
#   1   reboot required
#   2   fatal error (seen when Dell Core Services is missing)
if (-not $ApplyUpdates) {
    Write-Host "  DCU installed and configured. NOT applying updates (-ApplyUpdates not given)."
    Write-Host "  Re-run with -ApplyUpdates to actually install drivers and firmware on this machine."
    Add-ReminderIfMissing "[ ] Run tweaks\vendor-drivers.ps1 -ApplyUpdates to install Dell drivers/firmware"
    Write-Host "======================================="
    return
}

Write-Host "  Scanning and applying Dell updates (this can take a while)..."
& $dcuCli /applyUpdates -reboot=disable -outputLog=C:\MerionIT\dcu-apply.log 2>&1 |
    Where-Object { $_ -notmatch 'Downloading updates \(' } |
    ForEach-Object { Write-Host "    $_" }
$rc = $LASTEXITCODE
switch ($rc) {
    0   { Write-Host "  Dell updates applied." }
    500 { Write-Host "  No Dell updates available - already current." }
    1   { Write-Host "  Dell updates applied - REBOOT REQUIRED."
          Add-ReminderIfMissing "[ ] Reboot to finish Dell Command Update driver/firmware installs" }
    2   { Write-Warning "  dcu-cli returned 2 (fatal). Dell Core Services may be missing - reinstall DCU." }
    default { Write-Warning "  dcu-cli returned $rc - see C:\MerionIT\dcu-apply.log" }
}

Write-Host "======================================="
