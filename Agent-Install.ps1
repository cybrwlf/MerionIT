<#
RMM/monitoring agent check. Confirmed with Merion IT Admin: every property (MRM, MRQ, MRP, MIT, etc.)
uses the same Moorestown > CSU B Windows Agent Installer - no per-property lookup needed.

Runs automatically as part of 1st_Step.ps1 - detects whether the agent is already installed and
skips itself silently if so, so it never nags on a machine that already has it. If the agent
exists but is broken, that's a manual repair (download the installer and run it with -r-w) -
there's no reliable way to automatically tell "fine" apart from "broken", so that stays a human
call.

Detection confirmed live 2026-07-23 against a real Merion machine with the agent installed:
- The service's internal Name is a tenant-specific generated string (e.g.
  "KAPRCMPS02494867515003"), NOT a stable "Kaseya Agent"/"KaseyaAgent" name - only the
  DisplayName ("Kaseya Agent" / "Kaseya Agent Endpoint") is predictable across machines. Match
  on DisplayName, not Name.
- Get-Process -Name "AgentMon" missed the process entirely even though it was genuinely running
  (confirmed via Get-CimInstance Win32_Process) - a session/rights visibility gap, not a naming
  issue. Use Get-CimInstance Win32_Process instead of Get-Process for the process-based check.
#>

$agentUrl = "https://managedsupport.kaseya.net/mkDefault.asp?id=19275903"

$serviceFound = Get-Service | Where-Object { $_.DisplayName -like "*Kaseya Agent*" } | Select-Object -First 1
$processFound = $null
if (-not $serviceFound) {
    $processFound = Get-CimInstance Win32_Process -Filter "Name = 'AgentMon.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($serviceFound -or $processFound) {
    $how = if ($serviceFound) { "service: $($serviceFound.DisplayName)" } else { "process: AgentMon.exe (PID $($processFound.ProcessId))" }
    Write-Host "RMM agent already detected ($how) - skipping install."
    return
}

Write-Warning "RMM agent not detected."

# Reuse a cached copy from apps\ if we have one, rather than re-downloading every run - useful
# when testing/re-running setup repeatedly on the same machine in a single day. A stale copy
# (over a day old) is removed so a re-run after that always grabs a fresh installer instead of
# silently reusing one that might be outdated.
$appsDir = Join-Path $PSScriptRoot "apps"
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
    Write-Host "Opening the Windows Agent Installer download page (Moorestown > CSU B)..."
    Write-Host "Note: this install has never had a silent/unattended switch - the installer's own wizard still needs a human to click through it, same as always. This just saves hunting for the download."

    # Skip Edge's first-run experience before it ever opens - tweaks/basic10-11stuff.ps1 also
    # sets this, but that runs in 2nd/3rd Step, AFTER this script. Without it set here first,
    # this Start-Process below opens Edge for the very first time on the machine, which shows
    # the sign-in/import-settings wizard instead of navigating straight to $agentUrl - the
    # auto-download never fires and the polling loop below times out waiting for a file that
    # never arrives.
    If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Type DWord -Value 1 -ErrorAction SilentlyContinue

    $downloadsDir = Join-Path $env:USERPROFILE "Downloads"
    Start-Process $agentUrl

    Write-Host "Waiting for the download to finish (the link auto-downloads KcsSetup.exe, no click needed)..."
    $downloaded = $null
    $lastSize = -1
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Seconds 5
        $candidate = Get-ChildItem -Path $downloadsDir -Filter "KcsSetup*.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate -and $candidate.Length -eq $lastSize) {
            $downloaded = $candidate
            break
        }
        $lastSize = if ($candidate) { $candidate.Length } else { -1 }
    }

    if ($downloaded) {
        Write-Host "Moving $($downloaded.FullName) to $installerPath"
        Move-Item -Path $downloaded.FullName -Destination $installerPath -Force
    } else {
        Write-Warning "Didn't see the download land in $downloadsDir after 2 minutes - download it manually into $appsDir and re-run."
    }
}

if (Test-Path $installerPath) {
    Write-Host "Launching $installerPath - click through the installer as usual."
    # Poll rather than Start-Process -Wait: confirmed live 2026-07-29 that a Modern Standby
    # sleep/wake cycle during this human-paced wait can leave -Wait's process-exit handle stuck
    # even after the installer has already exited. Polling Get-Process directly sidesteps that.
    $proc = Start-Process -FilePath $installerPath -PassThru
    while (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 2
    }
} else {
    Write-Warning "No installer available to launch - download it manually into $appsDir and run it, or re-run this script."
}
Write-Host "If the agent turns out to already be installed under a different name, update the detection logic at the top of this script."
