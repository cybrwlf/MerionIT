#Requires -RunAsAdministrator
<#
Main orchestrator. Replaces Step1.bat, folding in the improvements that used to only exist in
Merion IT Admin's personal Step1.txt scratch notes (MRP company support, auto OS-detect to launch
2nd/3rd step). Also this is what RunOnce re-launches automatically after the rename reboot
(see RenamePC.ps1) - so it must be safe to run twice: it detects "already renamed" and skips
straight past the rename step.

Agent check and app install both run automatically every time (no menu) - Agent-Install.ps1
skips itself if the agent's already detected, and Install-Apps.ps1 updates anything already
installed rather than reinstalling. backup-userfiles.ps1 is intentionally NOT called from here -
that's a manual-only action (run it directly when offboarding someone), never automatic.

Once a full run finishes, this scrubs a handful of setup-only files that aren't needed once
the machine is live - denying anyone who later gets local access a blueprint of how initial
setup worked. SingleUser.ps1 is deliberately excluded from that cleanup since it's meant to
persist and get reused for later hires.

Writes .setup-complete once a full run finishes. If this script runs again later (e.g. bootstrap.ps1
was re-synced for an unrelated reason and happened to restore the blueprint files above), the
cleanup re-fires immediately - before anything else, regardless of whether you choose to continue
with a full pipeline re-run - so a restored blueprint file never survives past that point.

Full console output (including everything RenamePC.ps1/DefaultAccounts.ps1/Agent-Install.ps1/
Install-Apps.ps1 print, since they run in-process from here) is transcribed to
C:\MerionIT\logs\Step1-Accounts-Apps-<timestamp>.log. A rename reboot cuts the transcript short - RunOnce
starts a fresh one when this script relaunches after restart.

Reassigning an already-named machine to a new user: the rename gate below fires on any name that
doesn't start with MRM/MRQ/MRP/MIT (DESKTOP-xxxx, LAPTOP-xxxx, anything else a vendor ships), so a
machine that already has a Merion name would never be renamed through this script - it would fall
straight through to account setup and keep the old user's name forever.
Pass -ForceRename (plus the RenamePC.ps1 parameters you want) to take that path deliberately.
-Unattended additionally removes the two confirmation prompts here, so the whole thing can run
over Kaseya/SSH with no interactive console.
#>
param(
    # Normally inferred from the computer name. Needed with -ForceRename when the current name
    # is a factory one, and lets a machine move between companies.
    [ValidateSet('MRM', 'MRQ', 'MRP')]
    [string]$Company,

    # Run the rename step even though this machine already has an MRM/MRQ/MRP name.
    [switch]$ForceRename,

    # Passed straight through to RenamePC.ps1 - see its param block for meanings.
    [string]$Property,
    [ValidateSet('DT', 'LT')]
    [string]$MachineType,
    [string]$Year,
    [string]$UniqueId,
    [switch]$NoReboot,

    # Passed through to DefaultAccounts.ps1 as the MRQ named-user account.
    [string]$UserName,

    # Auto-answer the confirmation prompts in this script. Does NOT delete secrets.psd1 - that
    # needs -DeleteSecrets, deliberately, so a credential file is never removed by implication.
    [switch]$Unattended,

    [switch]$DeleteSecrets
)


# Prevent the machine sleeping/display-off while setup runs. Confirmed live 2026-07-29: on a
# fresh machine's default OOBE power settings, Modern Standby can trigger mid-wait during
# Agent-Install.ps1's human-paced installer wait, and the resume left Start-Process -Wait stuck
# watching a stale process handle even after the installer had already exited and finished.
# powerconfig.cmd (run later, in 2nd/3rd Step) still owns the machine's persistent power-plan
# settings - this is only a temporary, per-process override that reverts automatically when this
# script exits.
Add-Type -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);' -Name Power -Namespace Native
[Native.Power]::SetThreadExecutionState([uint32]2147483651) | Out-Null  # 0x80000003 = ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED (decimal, not hex - PowerShell parses 0x80000003 as a signed Int32 and [uint32] rejects negative values even though the bits match)

$MerionITRoot = "C:\MerionIT"
Set-Location $MerionITRoot
$CompletionMarker = Join-Path $MerionITRoot ".setup-complete"

$LogDir = Join-Path $MerionITRoot "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "Step1-Accounts-Apps-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log") | Out-Null

function Remove-SetupBlueprintFiles {
    param([string]$Root)
    $blueprintFiles = @(
        "setup\RenamePC.ps1",
        "setup\DefaultAccounts.ps1",
        "setup\MITUser.ps1"
    )
    foreach ($f in $blueprintFiles) {
        $path = Join-Path $Root $f
        if (Test-Path $path) {
            Remove-Item $path -Force
            Write-Host "Removed $f (setup-blueprint file - not needed once setup's done)."
        }
    }
}

if (Test-Path "$MerionITRoot\setup\updatePCtime.bat") {
    Start-Process cmd.exe -ArgumentList "/c `"$MerionITRoot\setup\updatePCtime.bat`"" -NoNewWindow -Wait
}

$computerName = $env:COMPUTERNAME
$prefix = $computerName.Substring(0, [Math]::Min(3, $computerName.Length))

# A machine already carrying one of our prefixes has been named. ANYTHING else (DESKTOP-xxxx,
# LAPTOP-xxxx, Computer-1234, a vendor/OEM name, a typo) is treated as a factory name and gets
# renamed. MIT is listed only so a loaner already named by RenamePC.ps1 -Company MIT isn't
# renamed again; Select-Company below has no MIT option.
$namedPrefixes = @('MRM', 'MRQ', 'MRP', 'MIT')

function Select-Company {
    Write-Host ""
    Write-Host "Select company"
    Write-Host "1  Merion (MRM)"
    Write-Host "2  Merion HQ (MRQ)"
    Write-Host "3  Merion Realty Partners (MRP)"
    $choice = Read-Host "Select number corresponding to which company"
    switch ($choice) {
        '1' { return 'MRM' }
        '2' { return 'MRQ' }
        '3' { return 'MRP' }
        default { Write-Warning "'$choice' is not valid, try again"; return Select-Company }
    }
}

# This has to stay ahead of the .setup-complete block below: that block scrubs RenamePC.ps1 off
# disk the moment it runs, so a rename attempted after it would find the script already gone.
if ($namedPrefixes -notcontains $prefix -or $ForceRename) {
    if ($ForceRename) {
        Write-Host "-ForceRename specified - renaming '$computerName' even though it isn't a factory name..."
    } else {
        Write-Host "Computer name '$computerName' isn't an MRM/MRQ/MRP name - renaming PC..."
    }

    if ($Company) {
        $renameCompany = $Company
    } elseif ($Unattended) {
        throw "-Unattended needs -Company as well - there's no console here to answer the company prompt."
    } else {
        $renameCompany = Select-Company
    }

    # Only forward the parameters actually supplied, so RenamePC.ps1 falls back to its own
    # detection/prompts for anything left out.
    $renameArgs = @{}
    foreach ($p in 'Property', 'MachineType', 'Year', 'UniqueId') {
        if ($PSBoundParameters.ContainsKey($p)) { $renameArgs[$p] = $PSBoundParameters[$p] }
    }
    if ($Unattended) { $renameArgs['Force'] = $true }
    if ($NoReboot) { $renameArgs['NoReboot'] = $true }

    & "$MerionITRoot\setup\RenamePC.ps1" -Company $renameCompany @renameArgs
    # RenamePC.ps1 reboots the machine (rename requires it) - nothing more to do this session.
    return
}

if (Test-Path $CompletionMarker) {
    # Re-scrub immediately, before anything else - if bootstrap.ps1 was re-run for an unrelated
    # reason and its sync happened to restore a blueprint file, it doesn't get to survive this.
    Remove-SetupBlueprintFiles -Root $MerionITRoot

    $completedOn = Get-Content $CompletionMarker -Raw
    Write-Warning "This machine looks already set up (completed $completedOn)."
    if ($Unattended) {
        Write-Host "-Unattended specified - continuing anyway. Tweaks will be reapplied and any Start Menu/taskbar customizations may be reset."
        $confirm = 'Y'
    } else {
        $confirm = Read-Host "Re-running will reapply tweaks and may reset Start Menu/taskbar customizations. Continue? [Y/N]"
    }
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Stopping here. If you just need to add a user or refresh an app, run SingleUser.ps1 / Install-Apps.ps1 directly instead."
        return
    }
}

# Company is already known from the computer name itself (set during the rename step above) -
# no need to ask again.
# NOT named $company: PowerShell variables are case-insensitive, so that would be the [Company]
# parameter above, and its ValidateSet rejects the $null a non-matching prefix produces.
$accountCompany = switch -Regex ($prefix) {
    '^MRM$' { 'MRM' }
    '^MRQ$' { 'MRQ' }
    '^MRP$' { 'MRP' }
    default { $null }
}

if ($Company) { $accountCompany = $Company }

# pcsadmin is created on every run regardless of company. With no company resolved (MIT, or a name
# that still isn't ours) DefaultAccounts.ps1 is called without -Company and does pcsadmin only.
$accountArgs = @{}
if ($accountCompany) {
    Write-Host "Computer name starts with '$prefix' - setting up default $accountCompany accounts..."
    $accountArgs['Company'] = $accountCompany
    if ($PSBoundParameters.ContainsKey('UserName')) { $accountArgs['UserName'] = $UserName }
    if ($PSBoundParameters.ContainsKey('PropertyCode')) { $accountArgs['PropertyCode'] = $PropertyCode }

    # The property code is the 4 digits already in the computer name - that's where it came from
    # when the machine was named - so only ask for it if the name doesn't carry one.
    if ($accountCompany -eq 'MRM' -and -not $accountArgs.ContainsKey('PropertyCode')) {
        $m = [regex]::Match($computerName, '^MRM(\d{4})-')
        if ($m.Success) {
            Write-Host "Using property code '$($m.Groups[1].Value)' from the computer name."
            $accountArgs['PropertyCode'] = $m.Groups[1].Value
        } elseif ($Unattended) {
            throw "-Unattended needs -PropertyCode for MRM: couldn't read a 4-digit property code out of the computer name '$computerName'."
        }
    }

    if ($Unattended -and -not $accountArgs.ContainsKey('UserName')) {
        # -Unattended has to mean "never prompt". Skipping is the safe default: it creates nothing.
        # Add the named account afterwards with SingleUser.ps1, which survives the end-of-run
        # cleanup precisely for this.
        Write-Host "-Unattended with no -UserName - skipping named user account creation. Use SingleUser.ps1 to add it later."
        $accountArgs['UserName'] = ''
    }
} else {
    Write-Warning "Computer name prefix '$prefix' has no company - creating pcsadmin only."
}

& "$MerionITRoot\setup\DefaultAccounts.ps1" @accountArgs
if (Test-Path "$MerionITRoot\tweaks\bginfo.ps1") {
    & "$MerionITRoot\tweaks\bginfo.ps1"
}

# Agent check - Agent-Install.ps1 detects an existing install and skips itself automatically.
& "$MerionITRoot\setup\Agent-Install.ps1"

# Apps always run - every machine should have the full standard set. Install-Apps.ps1 detects
# anything already present (even if installed manually) and updates it instead of reinstalling.
& "$MerionITRoot\setup\Install-Apps.ps1"

# Office always runs too - Fix-OfficeLanguages.ps1 already detects its own three cases (no Office
# -> install fresh, extra language packs -> clean up, already correct -> no-op), so it's safe to
# call unconditionally every time rather than relying on a tech to remember it's needed.
& "$MerionITRoot\setup\Fix-OfficeLanguages.ps1"

if (Test-Path "$MerionITRoot\secrets.psd1") {
    if ($DeleteSecrets) {
        $confirmDelete = 'Y'
    } elseif ($Unattended) {
        # Deliberately NOT deleted just because the run was unattended - removing a credential
        # file has to be asked for explicitly. The else branch below logs a reminder instead.
        $confirmDelete = 'N'
    } else {
        $confirmDelete = Read-Host "Account setup complete. Delete secrets.psd1 now? [Y/N]"
    }
    if ($confirmDelete -ieq 'Y') {
        Remove-Item "$MerionITRoot\secrets.psd1" -Force
        Write-Host "secrets.psd1 deleted."
    } else {
        Write-Warning "secrets.psd1 left in place - remember to delete it manually once setup is fully done."
        # Insert before the closing "====" banner line so this lands inside the checklist box
        # instead of trailing after it.
        $reminderPath = Join-Path $MerionITRoot "setup\Manual-Steps-Reminder.txt"
        $reminderLine = "[ ] Delete C:\MerionIT\secrets.psd1 - it was left in place during setup"
        if ((Test-Path $reminderPath) -and -not (Select-String -Path $reminderPath -Pattern ([regex]::Escape($reminderLine)) -Quiet)) {
            $content = @(Get-Content -Path $reminderPath)
            if ($content.Count -gt 0 -and $content[-1] -match '^=+$') {
                $newContent = $content[0..($content.Count - 2)] + $reminderLine + $content[-1]
            } else {
                $newContent = $content + $reminderLine
            }
            Set-Content -Path $reminderPath -Value $newContent
        }
    }
}

Remove-SetupBlueprintFiles -Root $MerionITRoot
Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Set-Content -Path $CompletionMarker

$osName = (Get-ComputerInfo).OsName
$stepTs = Get-Date -Format 'yyyy-MM-dd_HHmmss'
# Step 2 runs for a long time, so the tech has to SEE its "[Step N of 16]" lines. Redirecting its output
# to a file (what this used to do) left the console blank until the reminder opened. Now stdout is
# shown and kept in the log; stderr still goes to its own .err.log, written by cmd so PowerShell never
# touches it. This waits for Step 2 to finish (the reminder in Notepad is its last action).
function Start-Step2([string]$Bat, [string]$Tag) {
    $outLog = Join-Path $LogDir "$Tag-$stepTs.log"
    $errLog = Join-Path $LogDir "$Tag-$stepTs.err.log"
    Set-Location $MerionITRoot
    & cmd.exe /c "`"$Bat`" 2>>`"$errLog`"" | Tee-Object -FilePath $outLog
}
if ($osName -like "*Windows 11*") {
    Write-Host "Detected Windows 11 - launching Step2..."
    Start-Step2 "$MerionITRoot\setup\Step2-Tweaks-Win11.bat" "Step2-Tweaks-Win11"
} elseif ($osName -like "*Windows 10*") {
    Write-Host "Detected Windows 10 - launching Step2..."
    Start-Step2 "$MerionITRoot\setup\Step2-Tweaks-Win10.bat" "Step2-Tweaks-Win10"
} else {
    Write-Warning "Unrecognized OS ('$osName') - launch Step2-Tweaks-Win11.bat or Step2-Tweaks-Win10.bat manually."
}

Stop-Transcript | Out-Null
