<#
Handles the McAfee consumer trial that ships on a lot of OEM images (found on an acquired-property
Lenovo ThinkPad 2026-09-22, and Ricardo reports hitting it often).

READ THIS BEFORE CHANGING THE ORDER OF OPERATIONS.

McAfee cannot be removed silently. This is deliberate on McAfee's part, not a gap in this script:

  1. mccleanup.exe (the CLI engine inside MCPR) calls ValidateParentProcess and REFUSES to run
     unless McClnUI.exe is its parent. Launching it from PowerShell, from a SYSTEM scheduled task,
     or from Safe Mode all fail identically with "failed to validate parent module" and an instant
     exit printing "current process id: 0". Four approaches were tested on 2026-09-22; all four
     died on that single check.
  2. Even the genuine MCPR.exe fails with "ValidateParentProcess-write-registry failed" once
     McAfee has fully ACTIVATED (i.e. registered itself in SecurityCenter2 and taken the AV role
     from Defender). At that point its self-protection defends its own registry keys.

WHAT DOES WORK, and why the order below matters:

  On a fresh OEM image McAfee is usually DORMANT - installed, services running, but NOT registered
  as the antivirus (Defender still holds that role). In that state MCPR runs fine and reports
  "The products have been successfully removed."

  The trap: McAfee leaves reinstall hooks that survive MCPR. On the test machine MCPR succeeded at
  10:25, the machine rebooted, and the \McAfeeLogon scheduled task fired at 10:30 and put all of
  it back - this time ACTIVATED. From then on MCPR could no longer run at all.

  So: strip the hooks FIRST, then run MCPR, then reboot. Doing it the other way round costs you
  the machine (it took an afternoon to work that out).

This script does the parts that can be automated - detection, hook removal, and flagging the
manual step. The MCPR run itself needs a human, and there is no way around that.
#>

Write-Host "======================================="
Write-Host "Checking for McAfee (OEM trial)..."
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

# --- detect ---------------------------------------------------------------------
# Two independent signals: the ARP entry and the service controller. The ARP entry alone is not
# enough - a partial removal can leave services running with no entry, and vice versa.
$uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$mcArp = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -match 'McAfee' }
$mcSvc = Get-Service -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -match 'McAfee' -or $_.Name -match '^mfe' }

if (-not $mcArp -and -not $mcSvc) {
    Write-Host "  No McAfee found."
    Write-Host "======================================="
    return
}

Write-Host "  FOUND McAfee:"
if ($mcArp) { $mcArp | ForEach-Object { Write-Host "    $($_.DisplayName) [$($_.DisplayVersion)]" } }
Write-Host "    $(($mcSvc | Measure-Object).Count) services, $((($mcSvc | Where-Object Status -eq 'Running') | Measure-Object).Count) running"

# --- is it dormant or activated? -------------------------------------------------
# This decides whether MCPR will actually work, so tell the tech up front rather than letting
# them find out after a reboot.
$avProducts = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
$mcRegistered = $avProducts | Where-Object { $_.displayName -match 'McAfee' }
if ($mcRegistered) {
    Write-Warning "  McAfee is ACTIVATED (registered as the antivirus). MCPR will most likely fail"
    Write-Warning "  with 'ValidateParentProcess-write-registry failed' - its self-protection is up."
    Write-Warning "  A reimage is usually faster than fighting this."
} else {
    Write-Host "  McAfee is dormant (not the registered AV) - MCPR should work."
}

# --- strip the reinstall hooks ---------------------------------------------------
# THE important step. These are what restored McAfee after a successful MCPR run on 2026-09-22.
# Observed on a Lenovo OEM image: \McAfeeLogon, \McAfee Remediation (Prepare),
# \McAfee\DAD.Execute.Updates, \McAfee\McAfee Auto Maintenance Task Agent,
# \McAfee\McAfee Idle Detection Task.
Write-Host "  Removing McAfee reinstall hooks (scheduled tasks)..."
$removed = 0; $blocked = 0
foreach ($task in (Get-ScheduledTask -ErrorAction SilentlyContinue |
                   Where-Object { $_.TaskName -match 'McAfee' -or $_.TaskPath -match 'McAfee' })) {
    $full = "$($task.TaskPath)$($task.TaskName)"
    try {
        Stop-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
        Write-Host "    removed $full"
        $removed++
    } catch {
        Write-Warning "    BLOCKED $full - $($_.Exception.Message)"
        $blocked++
    }
}
if ($removed -eq 0 -and $blocked -eq 0) { Write-Host "    none found" }

# Run/RunOnce entries are a second restore path. Cheap to check.
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
               'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce') {
    (Get-ItemProperty $k -ErrorAction SilentlyContinue).PSObject.Properties |
        Where-Object { $_.Name -notlike 'PS*' -and ($_.Name -match 'McAfee' -or $_.Value -match 'McAfee') } |
        ForEach-Object {
            Remove-ItemProperty -Path $k -Name $_.Name -Force -ErrorAction SilentlyContinue
            Write-Host "    removed Run entry: $($_.Name)"
        }
}

# --- flag the manual step --------------------------------------------------------
# MCPR is shipped in C:\MerionIT\apps so the tech does not have to go find it. If it is missing,
# say so explicitly rather than pointing at a file that is not there.
$mcprPath = "C:\MerionIT\apps\MCPR.exe"
if (Test-Path $mcprPath) {
    Add-ReminderIfMissing "[ ] Remove McAfee: run C:\MerionIT\apps\MCPR.exe as admin, then REBOOT (hooks already cleared by the script)"
    Write-Host "  MCPR is staged at $mcprPath"
} else {
    Add-ReminderIfMissing "[ ] Remove McAfee: download MCPR from https://download.mcafee.com/molbin/iss-loc/SupportTools/MCPR/MCPR.exe, run as admin, then REBOOT"
    Write-Warning "  MCPR.exe not found at $mcprPath - reminder points at the download URL instead."
}
Write-Host "  Added to Manual-Steps-Reminder.txt."
Write-Host "  NOTE: McAfee removal cannot be silent - mccleanup.exe validates its parent process."
Write-Host "======================================="
