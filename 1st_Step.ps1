#Requires -RunAsAdministrator
<#
Main orchestrator. Replaces 1st_Step.bat, folding in the improvements that used to only exist in
Merion IT Admin's personal 1st_Step.txt scratch notes (MRP company support, auto OS-detect to launch
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
C:\MerionIT\logs\1st_Step-<timestamp>.log. A rename reboot cuts the transcript short - RunOnce
starts a fresh one when this script relaunches after restart.

Reassigning an already-named machine to a new user: the rename gate below only fires on a
factory "DES*" name, so a machine that already has a Merion name could never be renamed through
this script - it fell straight through to account setup and kept the old user's name forever.
Pass -ForceRename (plus the RenamePC.ps1 parameters you want) to take that path deliberately.
-Unattended additionally removes the two confirmation prompts here, so the whole thing can run
over Kaseya/SSH with no interactive console.
#>
param(
    # Normally inferred from the computer name. Needed with -ForceRename when the current name
    # is a factory one, and lets a machine move between companies.
    [ValidateSet('MRM', 'MRQ', 'MRP')]
    [string]$Company,

    # Run the rename step even though this machine already has a non-"DES" name.
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
Start-Transcript -Path (Join-Path $LogDir "1st_Step-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log") | Out-Null

function Remove-SetupBlueprintFiles {
    param([string]$Root)
    $blueprintFiles = @(
        "RenamePC.ps1",
        "DefaultAccounts.ps1",
        "MITUser.ps1"
    )
    foreach ($f in $blueprintFiles) {
        $path = Join-Path $Root $f
        if (Test-Path $path) {
            Remove-Item $path -Force
            Write-Host "Removed $f (setup-blueprint file - not needed once setup's done)."
        }
    }
}

if (Test-Path "$MerionITRoot\updatePCtime.bat") {
    Start-Process cmd.exe -ArgumentList "/c `"$MerionITRoot\updatePCtime.bat`"" -NoNewWindow -Wait
}

$computerName = $env:COMPUTERNAME
$prefix = $computerName.Substring(0, [Math]::Min(3, $computerName.Length))

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
if ($prefix -ieq "DES" -or $ForceRename) {
    if ($ForceRename) {
        Write-Host "-ForceRename specified - renaming '$computerName' even though it isn't a factory name..."
    } else {
        Write-Host "Computer name starts with 'DES' - renaming PC..."
    }

    if ($Company) {
        $company = $Company
    } elseif ($Unattended) {
        throw "-Unattended needs -Company as well - there's no console here to answer the company prompt."
    } else {
        $company = Select-Company
    }

    # Only forward the parameters actually supplied, so RenamePC.ps1 falls back to its own
    # detection/prompts for anything left out.
    $renameArgs = @{}
    foreach ($p in 'Property', 'MachineType', 'Year', 'UniqueId') {
        if ($PSBoundParameters.ContainsKey($p)) { $renameArgs[$p] = $PSBoundParameters[$p] }
    }
    if ($Unattended) { $renameArgs['Force'] = $true }
    if ($NoReboot) { $renameArgs['NoReboot'] = $true }

    & "$MerionITRoot\RenamePC.ps1" -Company $company @renameArgs
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
$company = switch -Regex ($prefix) {
    '^MRM$' { 'MRM' }
    '^MRQ$' { 'MRQ' }
    '^MRP$' { 'MRP' }
    default { $null }
}

if ($Company) { $company = $Company }

if ($company) {
    Write-Host "Computer name starts with '$prefix' - setting up default $company accounts..."
    $accountArgs = @{}
    if ($PSBoundParameters.ContainsKey('UserName')) { $accountArgs['UserName'] = $UserName }
    if ($PSBoundParameters.ContainsKey('PropertyCode')) { $accountArgs['PropertyCode'] = $PropertyCode }

    if ($Unattended) {
        # -Unattended has to mean "never prompt". Both of DefaultAccounts.ps1's remaining
        # Read-Host calls are reachable from here, so supply an answer for each rather than
        # letting the run hang on a console nobody is watching.
        if (-not $accountArgs.ContainsKey('UserName')) {
            # Skipping is the safe default: it creates nothing. Add the named account afterwards
            # with SingleUser.ps1, which survives the end-of-run cleanup precisely for this.
            Write-Host "-Unattended with no -UserName - skipping named user account creation. Use SingleUser.ps1 to add it later."
            $accountArgs['UserName'] = ''
        }
        if ($company -eq 'MRM' -and -not $accountArgs.ContainsKey('PropertyCode')) {
            # The property code is the 4 digits already in the computer name - that's where it
            # came from when the machine was named.
            $m = [regex]::Match($computerName, '^MRM(\d{4})-')
            if (-not $m.Success) {
                throw "-Unattended needs -PropertyCode for MRM: couldn't read a 4-digit property code out of the computer name '$computerName'."
            }
            Write-Host "-Unattended with no -PropertyCode - using '$($m.Groups[1].Value)' from the computer name."
            $accountArgs['PropertyCode'] = $m.Groups[1].Value
        }
    }

    & "$MerionITRoot\DefaultAccounts.ps1" -Company $company @accountArgs
    if (Test-Path "$MerionITRoot\tweaks\bginfo.ps1") {
        & "$MerionITRoot\tweaks\bginfo.ps1"
    }
} else {
    Write-Warning "Computer name prefix '$prefix' not recognized (expected DES/MRM/MRQ/MRP). Skipping default account setup."
}

# Agent check - Agent-Install.ps1 detects an existing install and skips itself automatically.
& "$MerionITRoot\Agent-Install.ps1"

# Apps always run - every machine should have the full standard set. Install-Apps.ps1 detects
# anything already present (even if installed manually) and updates it instead of reinstalling.
& "$MerionITRoot\Install-Apps.ps1"

# Office always runs too - Fix-OfficeLanguages.ps1 already detects its own three cases (no Office
# -> install fresh, extra language packs -> clean up, already correct -> no-op), so it's safe to
# call unconditionally every time rather than relying on a tech to remember it's needed.
& "$MerionITRoot\Fix-OfficeLanguages.ps1"

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
        $reminderPath = Join-Path $MerionITRoot "Manual-Steps-Reminder.txt"
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
if ($osName -like "*Windows 11*") {
    Write-Host "Detected Windows 11 - launching 2nd_Step..."
    Start-Process "$MerionITRoot\2nd_Step_WIN11.bat" -WorkingDirectory $MerionITRoot -NoNewWindow `
        -RedirectStandardOutput (Join-Path $LogDir "2nd_Step_WIN11-$stepTs.log") `
        -RedirectStandardError (Join-Path $LogDir "2nd_Step_WIN11-$stepTs.err.log")
} elseif ($osName -like "*Windows 10*") {
    Write-Host "Detected Windows 10 - launching 3rd_Step..."
    Start-Process "$MerionITRoot\3rd_Step_WIN10.bat" -WorkingDirectory $MerionITRoot -NoNewWindow `
        -RedirectStandardOutput (Join-Path $LogDir "3rd_Step_WIN10-$stepTs.log") `
        -RedirectStandardError (Join-Path $LogDir "3rd_Step_WIN10-$stepTs.err.log")
} else {
    Write-Warning "Unrecognized OS ('$osName') - launch 2nd_Step_WIN11.bat or 3rd_Step_WIN10.bat manually."
}

Stop-Transcript | Out-Null
