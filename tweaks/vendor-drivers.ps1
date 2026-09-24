<#
Vendor-specific driver handling.

Merion buys Dell, but acquired properties arrive with whatever they had, so this branches on the
manufacturer rather than assuming.

  Dell           remove SupportAssist, install Dell Command Update, tame it, run it
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

Write-Host "======================================="
Write-Host "Vendor driver handling..."
Write-Host "======================================="

$ReminderPath = "C:\MerionIT\Manual-Steps-Reminder.txt"
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

if ($manufacturer -notmatch 'Dell') {
    Write-Host "  Not a Dell - Windows Update handles drivers on this machine."
    Write-Host "  (WU policy is set by basic10-11stuff.ps1: 7-day quality deferral, feature"
    Write-Host "   updates unmanaged.)"
    Write-Host "======================================="
    return
}

# ---------------------------------------------------------------------------------
# Dell path
# ---------------------------------------------------------------------------------

# SupportAssist is the nagware - the thing that actually interrupts users. DCU is not, once
# configured below. Removing SupportAssist also takes Dell Client Management Service, Dell TechHub
# and Dell SupportAssist service with it (verified 2026-09-22); DCU reinstalls what it needs.
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
$uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$saMsi = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -eq 'Dell SupportAssist' } | Select-Object -First 1
if ($saMsi) {
    $p = Start-Process msiexec.exe -ArgumentList @('/x', $saMsi.PSChildName, '/qn', '/norestart') -Wait -PassThru
    Write-Host "    msi uninstall exit: $($p.ExitCode)   (0 or 3010 = success)"
}

# --- Dell Command Update -----------------------------------------------------------
$dcuCli = "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"

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
    else {
        # No USB. Remote machines (Kaseya-only, no way to hand-carry the installer) are the normal
        # case for this, so fall back to winget rather than giving up. Dell.CommandUpdate is the
        # Classic build and lands in the same ProgramFiles(x86) path checked above. It trails the
        # dell.com release slightly (5.7.0 vs 5.7.2 on 2026-09-23), which is fine - the /configure
        # switches below are identical across 5.7.x.
        Write-Host "  No installer in C:\MerionIT\apps - trying winget..."
        if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
            & winget.exe install --id Dell.CommandUpdate -e --silent `
                --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            Write-Host "    winget exit: $LASTEXITCODE"
            Start-Sleep -Seconds 10
        } else {
            Write-Warning "  winget not available either."
        }
    }

    if (-not (Test-Path $dcuCli)) {
        Write-Warning "  dcu-cli.exe still not present after install - giving up."
        Add-ReminderIfMissing "[ ] Dell Command Update install failed - install manually and rerun tweaks\vendor-drivers.ps1"
        Write-Host "======================================="
        return
    }
}
Write-Host "  dcu-cli: $((Get-Item $dcuCli).VersionInfo.ProductVersion)"

# Health probe. Test-Path on dcu-cli.exe is NOT sufficient: a partial uninstall leaves the binary
# on disk while removing Dell Core Services, and every dcu-cli call then returns 2. The presence
# check above passes, the script proceeds, and all six /configure calls plus the scan fail.
# Observed on MRM8035-LT101 2026-09-23 after the debloat script had uninstalled DCU mid-run
# (see commit 82b7303) - dcu-cli.exe 5.7.2.7 present, every invocation exit 2.
& $dcuCli /configure -scheduleManual -silent 2>&1 | Out-Null
if ($LASTEXITCODE -eq 2) {
    Write-Warning "  dcu-cli is present but non-functional (exit 2 - Dell Core Services missing)."
    Write-Warning "  Repair: winget uninstall --id Dell.CommandUpdate, reboot, then reinstall."
    Add-ReminderIfMissing "[ ] Dell Command Update is broken (dcu-cli exit 2) - uninstall it, reboot, reinstall, then rerun tweaks\vendor-drivers.ps1"
    Write-Host "======================================="
    return
}

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
