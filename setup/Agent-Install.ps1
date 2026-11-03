<#
RMM/monitoring agent check. Confirmed with Merion IT Admin: every company (MRM, MIP, MRQ, MRP, MIT)
uses the same Moorestown > CSU B Windows Agent Installer - no per-company lookup needed. The machine
is moved to its proper group in the Kaseya portal by hand afterwards (MIP confirmed 2026-11-03).

Runs automatically as part of Step1-Accounts-Apps.ps1. If the agent is already installed it is not
reinstalled, but its health is checked and reported (report only, nothing is changed): both Kaseya
services running, AgentMon.exe running, and a live connection to the Kaseya server. There's no
reliable way to tell "broken" from "slow to check in", so a bad result only prints the repair command
and adds a reminder line.

-Repair reinstalls over an existing agent with KcsSetup /s /r /w (/r reinstall even if present, /w
overwrite the config with the package's). This is Ricardo's long-standing fix for an agent that stops
working or keeps an old machine name. Because the package is Moorestown > CSU B, expect to have to
move the machine back to its group in the portal; a reminder line says so.

Renames: the agent keeps the name it registered with. When Step1-Accounts-Apps.ps1 renames a machine
that already has the agent, it writes C:\MerionIT\.agent-repair-pending (holding the old name). The
next run of this script after the rename has taken effect does the repair automatically and removes
the marker once the agent is confirmed healthy (decided 2026-11-03).

Detection confirmed live 2026-07-23 against a real Merion machine with the agent installed:
- The service's internal Name is a tenant-specific generated string (e.g.
  "KAPRCMPS02494867515003"), NOT a stable "Kaseya Agent"/"KaseyaAgent" name - only the
  DisplayName ("Kaseya Agent" / "Kaseya Agent Endpoint") is predictable across machines. Match
  on DisplayName, not Name.
- Get-Process -Name "AgentMon" missed the process entirely even though it was genuinely running
  (confirmed via Get-CimInstance Win32_Process) - a session/rights visibility gap, not a naming
  issue. Use Get-CimInstance Win32_Process instead of Get-Process for the process-based check.
#>
param(
    # Reinstall over an existing agent (/s /r /w). See above.
    [switch]$Repair
)

$agentUrl = "https://managedsupport.kaseya.net/mkDefault.asp?id=19275903"

$MerionITRoot = Split-Path $PSScriptRoot -Parent
$repairMarker = Join-Path $MerionITRoot ".agent-repair-pending"

$ReminderPath = Join-Path $MerionITRoot "setup\Manual-Steps-Reminder.txt"
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

# Report only. All three signals were seen healthy on MIP3004-LT601 2026-11-03, including after a
# reboot: both services Running, AgentMon.exe running, and an established connection from a Kaseya
# process (to port 5721 there). The connection can lag a service start, so it is polled for a minute.
function Get-AgentProblems {
    $services = @(Get-Service | Where-Object { $_.DisplayName -like "*Kaseya Agent*" })
    if (-not $services) { return @('no Kaseya Agent service') }
    $problems = @()
    foreach ($s in $services) {
        if ($s.Status -ne 'Running') { $problems += "service '$($s.DisplayName)' is $($s.Status)" }
    }
    if (-not (Get-CimInstance Win32_Process -Filter "Name = 'AgentMon.exe'" -ErrorAction SilentlyContinue)) {
        $problems += 'AgentMon.exe is not running'
    }
    $connected = $false
    for ($i = 0; $i -lt 12 -and -not $connected; $i++) {
        $agentPids = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -like '*\Kaseya\*' } | ForEach-Object { $_.ProcessId })
        $connected = [bool](Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
            Where-Object { $agentPids -contains $_.OwningProcess })
        if (-not $connected) { Start-Sleep -Seconds 5 }
    }
    if (-not $connected) { $problems += 'no connection from the agent to the Kaseya server after 60 s' }
    return $problems
}

$doRepair = [bool]$Repair
if (-not $doRepair -and (Test-Path $repairMarker)) {
    $oldName = (Get-Content $repairMarker -Raw).Trim()
    if ($env:COMPUTERNAME -ieq $oldName) {
        Write-Warning "An agent repair is waiting on a rename that hasn't taken effect yet (still '$oldName'). Reboot if a rename is staged, then run this again. If the rename was cancelled, delete $repairMarker."
    } else {
        Write-Host "Renamed from '$oldName' to '$env:COMPUTERNAME' - reinstalling the agent so it picks up the new name."
        $doRepair = $true
    }
}

$serviceFound = Get-Service | Where-Object { $_.DisplayName -like "*Kaseya Agent*" } | Select-Object -First 1
$processFound = $null
if (-not $serviceFound) {
    $processFound = Get-CimInstance Win32_Process -Filter "Name = 'AgentMon.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
}

if (($serviceFound -or $processFound) -and -not $doRepair) {
    $how = if ($serviceFound) { "service: $($serviceFound.DisplayName)" } else { "process: AgentMon.exe (PID $($processFound.ProcessId))" }
    Write-Host "RMM agent already detected ($how) - skipping install. Checking its health..."
    $problems = @(Get-AgentProblems)
    if ($problems) {
        foreach ($p in $problems) { Write-Warning "Agent health: $p" }
        Write-Host "To reinstall it: $PSCommandPath -Repair"
        Add-ReminderIfMissing "[ ] Kaseya agent looked unhealthy at setup - run C:\MerionIT\setup\Agent-Install.ps1 -Repair"
    } else {
        Write-Host "Agent health: services running, connected to the Kaseya server."
    }
    return
}

if ($doRepair -and -not ($serviceFound -or $processFound)) {
    Write-Host "No agent installed to repair - doing a normal install instead."
    $doRepair = $false
} elseif (-not $doRepair) {
    Write-Warning "RMM agent not detected."
}

# Reuse a cached copy from apps\ if we have one, rather than re-downloading every run - useful
# when testing/re-running setup repeatedly on the same machine in a single day. A stale copy
# (over a day old) is removed so a re-run after that always grabs a fresh installer instead of
# silently reusing one that might be outdated.
$appsDir = Join-Path $MerionITRoot "apps"
New-Item -ItemType Directory -Path $appsDir -Force | Out-Null
$installerPath = Join-Path $appsDir "KcsSetup.exe"

if (Test-Path $installerPath) {
    $ageDays = ((Get-Date) - (Get-Item $installerPath).LastWriteTime).TotalDays
    if ($ageDays -ge 1) {
        Write-Host "Cached installer in $appsDir is over a day old - removing so we grab a fresh copy."
        Remove-Item $installerPath -Force
    }
}

if (Test-Path $installerPath) {
    Write-Host "Using cached installer already in $appsDir (downloaded less than a day ago) - skipping re-download."
} else {
    # Downloaded directly, no browser. This used to open $agentUrl in Edge and wait 2 minutes for
    # KcsSetup.exe to show up in Downloads. On MIP3004-LT601 (2026-11-02) nothing ever landed, not even
    # a partial file, and the script had no way to see why (a SmartScreen hold, a slow link and browser
    # state are all invisible from here). Checked 2026-11-03: the link serves the signed exe straight
    # back (application/vnd.microsoft.portable-executable, ~59 MB, Agent Installer 9.5.0.53), so a
    # plain download works, including with nobody signed in.
    Write-Host "Downloading the Windows Agent Installer (Moorestown > CSU B, ~59 MB)..."
    # .exe extension on purpose: Get-AuthenticodeSignature can't check a file it doesn't recognise.
    $partialPath = Join-Path $appsDir "KcsSetup.partial.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        # The progress bar makes Invoke-WebRequest many times slower on PowerShell 5.1.
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $agentUrl -OutFile $partialPath -UseBasicParsing -ErrorAction Stop
        $sig = Get-AuthenticodeSignature -FilePath $partialPath
        if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'O=Kaseya Holdings Inc') {
            Move-Item -Path $partialPath -Destination $installerPath -Force
            Write-Host "Downloaded and verified: $('{0:N0}' -f (Get-Item $installerPath).Length) bytes, signed by Kaseya."
        } else {
            Write-Warning "Downloaded file failed the signature check (status: $($sig.Status), signer: $($sig.SignerCertificate.Subject)) - not using it."
            Remove-Item $partialPath -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Agent download failed: $($_.Exception.Message)"
        Remove-Item $partialPath -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path $installerPath) {
    # Silent. This used to launch the wizard for a human to click through, on the belief that it had no
    # silent switch. Kaseya documents one: /s "runs silently, suppressing all dialogs", /e exits if an
    # agent is already installed, /r reinstalls even if one is, /w overwrites the existing config
    # (help.vsa9.kaseya.com/help/Content/VSA/493.htm). The group and server are baked into the package,
    # so nothing else is passed. Kaseya does not document exit codes, so success is judged by the agent
    # itself afterwards, not by the exit code.
    $switches = if ($doRepair) { @('/s', '/r', '/w') } else { @('/s', '/e') }
    Write-Host "$(if ($doRepair) { 'Reinstalling' } else { 'Installing' }) the RMM agent silently ($installerPath $($switches -join ' '))..."
    # Poll rather than Start-Process -Wait: confirmed live 2026-07-29 that a Modern Standby
    # sleep/wake cycle during this wait can leave -Wait's process-exit handle stuck even after the
    # installer has already exited. Polling Get-Process directly sidesteps that.
    $proc = Start-Process -FilePath $installerPath -ArgumentList $switches -PassThru
    $deadline = (Get-Date).AddMinutes(15)
    while ((Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
    }
    if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
        Write-Warning "Agent installer still running after 15 minutes - not waiting any longer."
    }
    $installed = $null
    for ($i = 0; $i -lt 24 -and -not $installed; $i++) {
        $installed = Get-Service | Where-Object { $_.DisplayName -like "*Kaseya Agent*" } | Select-Object -First 1
        if (-not $installed) { Start-Sleep -Seconds 5 }
    }
    if (-not $installed) {
        Write-Warning "Agent installer finished but no Kaseya Agent service appeared. Run $installerPath by hand to see its error."
        Write-Host "If the agent turns out to already be installed under a different name, update the detection logic at the top of this script."
        return
    }
    $problems = @(Get-AgentProblems)
    if ($problems) {
        foreach ($p in $problems) { Write-Warning "Agent health after install: $p" }
        Write-Host "To try again: $PSCommandPath -Repair"
        Add-ReminderIfMissing "[ ] Kaseya agent looked unhealthy at setup - run C:\MerionIT\setup\Agent-Install.ps1 -Repair"
        return
    }
    # Only a confirmed healthy agent clears a pending rename repair; otherwise the next run tries again.
    Remove-Item $repairMarker -Force -ErrorAction SilentlyContinue
    if ($doRepair) {
        Write-Host "RMM agent reinstalled and healthy. Check this machine in the Kaseya portal and move it to its proper group."
        Add-ReminderIfMissing "[ ] Kaseya agent was reinstalled (/r /w) - check this machine in the Kaseya portal and move it to its proper group"
    } else {
        Write-Host "RMM agent installed and healthy. Move the machine to its proper group in the Kaseya portal."
    }
} else {
    Write-Warning "No installer available to launch - download it manually into $appsDir and run it, or re-run this script."
}
