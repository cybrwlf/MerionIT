# tools/

Operational scripts for machines that are **already deployed**. Everything in `tweaks/` runs during
provisioning; everything here runs afterwards, usually through Kaseya, usually on a machine with a
user sitting in front of it who should not be interrupted.

Both scripts run fine as **SYSTEM with nobody logged on**. Neither prompts, opens a window, or
needs a user profile.

| Script | Use it when |
|---|---|
| `Repair-MerionWindowsUpdate.ps1` | Auditing or fixing Windows Update policy. Safe fleet-wide. |
| `Diag-WindowsUpdate.ps1` | One machine is stuck in an update loop. **Not** a fleet tool. |

---

## Repair-MerionWindowsUpdate.ps1

Brings a deployed machine's Windows Update policy to the current Merion standard without
re-provisioning it, and reports whether the machine can move to Windows 11.

### Why it exists

Machines built before 2026-09-22 carry three defects from the old `basic10-11stuff.ps1`. All three
were found on real machines, not theorised:

1. **Automatic updates switched off entirely** — `NoAutoUpdate=1` and `AUOptions=1`. Machines were
   not pinned to an old build, they were told never to look. `MRM8035-LT101` was found sitting at a
   June 2024 patch level after two years of daily use at a property.
2. **The "managed by your organization" banner** — comes from `NoAutoRebootWithLoggedOnUsers` under
   the same `AU` key, not from the deferral values.
3. **Driver offers wrong for the vendor** — on Dell, DCU owns drivers and Windows Update offering
   them too produces phantom updates that can never install; on every other vendor Windows Update is
   the only driver path and must stay free to offer them.

Confirmed identical on three machines across three properties, laptop and desktop.

### Parameters

| Parameter | Effect |
|---|---|
| `-ReportOnly` | **Changes nothing.** Use for the fleet sweep. Never invokes `dcu-cli`. |
| `-AddToReminder` | Writes findings into `C:\MerionIT\Manual-Steps-Reminder.txt`. Used by `2nd_Step`/`3rd_Step`. Leave off for sweeps. |
| *(neither)* | Repairs what it can and reports what still needs a human. |

### Kaseya — audit a machine (safe, changes nothing)

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$d = "$env:SystemRoot\Temp\MerionIT"; $f = "$d\Repair-MerionWindowsUpdate.ps1"
New-Item -ItemType Directory -Path $d -Force | Out-Null
if (Test-Path $f) { Remove-Item $f -Force }
Invoke-WebRequest 'https://raw.githubusercontent.com/cybrwlf/MerionIT/master/tools/Repair-MerionWindowsUpdate.ps1' -OutFile $f -UseBasicParsing
powershell.exe -ExecutionPolicy Bypass -File $f -ReportOnly
```

### Kaseya — repair a machine

Identical, but drop `-ReportOnly` from the last line. Audit first, repair once you've seen what the
fleet looks like.

### Reading the output

Every run ends with one machine-readable line:

```
RESULT|MRM8020-DT801|Dell Inc.|win10-EOL|22H2 19045.6466|dcu=absent|win11=ready|issues=6|mode=report|v=2026-09-23.5
```

| Field | Meaning |
|---|---|
| 3rd | `win11` or `win10-EOL`. Windows 10 is out of support, so `win10-EOL` is a cost decision. |
| `dcu=` | `working`, `BROKEN (exit 2)`, `absent`, or `n/a` on non-Dell. `absent` on a Dell means no OEM driver path. |
| `win11=` | `ready`, `BLOCKED:<reasons>`, `CPU-unknown`, or `n/a` on machines already running Windows 11. |
| `issues=` | Count of findings. `0` means the machine was already correct. |
| `v=` | Script version that produced the line. Mismatched versions across a sweep mean a stale download, not a real difference between machines. |

Collect and sort:

```powershell
Get-Content .\sweep-output.txt | Select-String '^RESULT\|' | ForEach-Object {
    $p = $_.Line -split '\|'
    [PSCustomObject]@{
        Host   = $p[1]
        OS     = $p[3]
        Build  = $p[4]
        DCU    = $p[5]
        Win11  = $p[6]
        Issues = [int]($p[7] -replace 'issues=')
    }
} | Sort-Object Issues -Descending | Format-Table -AutoSize
```

### What it deliberately will not do

**It will not suppress Windows Update driver offers on a Dell whose DCU is broken or absent.** That
would leave the machine with no driver path at all. It reports `ACTION NEEDED` and leaves Windows
Update available until someone runs `tweaks\vendor-drivers.ps1`.

**It will not guess at CPU support.** Intel Core generation 8 and newer is the documented Windows 11
boundary and is classified automatically. Xeon, Pentium, Celeron, Atom and AMD return `CPU-unknown`
for a human, because their rules are not a clean generational line and a confident wrong answer here
sends someone out to buy hardware they did not need.

---

## Diag-WindowsUpdate.ps1

Diagnoses a Windows Update loop — the "installs in seconds, demands a reboot, comes back with the
same list" symptom — then resets the update stack.

**This is a single-machine troubleshooting tool.** By default it resets Windows Update, so running
it across a fleet would clear the update stack on every machine it touched. Use `-NoReset` if you
only want the diagnostics.

### How to use it

Run it, reboot, run it again. Each run writes a timestamped log to `C:\MerionIT\logs\wu-diag-*.txt`
and lists the previous runs, so comparing run N to run N+1 shows what a single reboot cycle actually
accomplished. That is the question a screenshot of the Settings page cannot answer.

### Order matters, and it is not an accident

Diagnostics are captured **before** the reset. The reset deletes `SoftwareDistribution`, and the
update history lives inside it — resetting first destroys the evidence. This matters because the
history is what separates the two failure modes:

- An update reporting **ResultCode 2 (Succeeded)** that then reappears is being installed and
  re-offered. Nothing is corrupt and no amount of resetting will help.
- An update reporting **4 (Failed)** is being rejected, and the HResult says why.

They need completely different fixes.

### Kaseya

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$d = "$env:SystemRoot\Temp\MerionIT"; $f = "$d\Diag-WindowsUpdate.ps1"
New-Item -ItemType Directory -Path $d -Force | Out-Null
if (Test-Path $f) { Remove-Item $f -Force }
Invoke-WebRequest 'https://raw.githubusercontent.com/cybrwlf/MerionIT/master/tools/Diag-WindowsUpdate.ps1' -OutFile $f -UseBasicParsing
powershell.exe -ExecutionPolicy Bypass -File $f
```

Add `-NoReset` to collect without clearing anything.

**Retrieve the log file, do not rely on console output.** This script uses `Start-Transcript`, so
the complete record is in `C:\MerionIT\logs\wu-diag-*.txt` regardless of what Kaseya captures from
the console. Pull the newest one:

```powershell
Get-ChildItem C:\MerionIT\logs\wu-diag-*.txt | Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 | Get-Content
```

### What it collects

Build and UBR, every pending-reboot flag Windows uses (CBS, Windows Update,
`PendingFileRenameOperations`, `WinSxS\pending.xml`), service state, update history with result
codes and HResults, pending updates, `WindowsUpdateClient` and Setup event logs, phantom and problem
PnP devices, installed driver versions for Intel/Realtek/HP/Dell, and a DISM `CheckHealth`.

The device and driver sections earn their place. On `MRM8035-LT101` the pending list was almost
entirely drivers — seven superseded Intel graphics extensions against a newer one already installed,
and HP printer drivers for devices whose PnP status was `Unknown`. Windows will not downgrade a
driver or install one for absent hardware, so they sat pending forever behind a restart prompt that
no pending-reboot flag agreed with.

---

## Notes that apply to both

### GitHub caching will hand you a stale script

`raw.githubusercontent.com` caches by path for several minutes and **ignores query strings**, so
cache-busting with `?t=123` does not work. If you have just pushed a change and need it immediately,
use a commit-pinned URL — a different path, therefore always a cache miss:

```
https://raw.githubusercontent.com/cybrwlf/MerionIT/<commit-sha>/tools/<script>.ps1
```

For routine use `master` is fine.

### Assert the version rather than hope

Across a sweep, one endpoint running a stale copy looks like a real difference between machines and
you will chase it. Fail fast instead:

```powershell
$v = (Select-String -Path $f -Pattern "ScriptVersion = '(.+)'").Matches.Groups[1].Value
if ($v -ne '2026-09-23.5') { throw "wrong version: '$v' - aborting rather than running a stale copy" }
```

Only `Repair-MerionWindowsUpdate.ps1` carries `$ScriptVersion` today.

### Why the commands look the way they do

| | |
|---|---|
| `-UseBasicParsing` | Without it, `Invoke-WebRequest` uses the IE engine, which needs a user profile that has been through IE first-run. As SYSTEM with nobody logged on, that fails. |
| The TLS line | PowerShell 5.1 does not always negotiate TLS 1.2, and GitHub requires it. Without it you get a connection error that looks like a network problem. |
| `$env:SystemRoot\Temp` | SYSTEM-writable and does not depend on a user profile existing. |
| `Remove-Item` before download | A failed download then cannot silently leave an old copy in place to run. |
