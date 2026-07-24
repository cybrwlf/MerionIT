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

Write-Warning "RMM agent not detected - opening the Windows Agent Installer download page (Moorestown > CSU B)..."
Start-Process $agentUrl
Write-Host "Download and run the installer as Administrator."
Write-Host "If the agent turns out to already be installed under a different name, update the detection logic at the top of this script."
