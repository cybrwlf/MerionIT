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
#>

$MerionITRoot = "C:\MerionIT"
Set-Location $MerionITRoot
$CompletionMarker = Join-Path $MerionITRoot ".setup-complete"

function Remove-SetupBlueprintFiles {
    param([string]$Root)
    $blueprintFiles = @(
        "RenamePC.ps1",
        "DefaultAccounts.ps1",
        "MITUser.ps1",
        "secrets.template.psd1"
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

if ($prefix -ieq "DES") {
    Write-Host "Computer name starts with 'DES' - renaming PC..."
    $company = Select-Company
    & "$MerionITRoot\RenamePC.ps1" -Company $company
    # RenamePC.ps1 reboots the machine (rename requires it) - nothing more to do this session.
    return
}

if (Test-Path $CompletionMarker) {
    # Re-scrub immediately, before anything else - if bootstrap.ps1 was re-run for an unrelated
    # reason and its sync happened to restore a blueprint file, it doesn't get to survive this.
    Remove-SetupBlueprintFiles -Root $MerionITRoot

    $completedOn = Get-Content $CompletionMarker -Raw
    Write-Warning "This machine looks already set up (completed $completedOn)."
    $confirm = Read-Host "Re-running will reapply tweaks and may reset Start Menu/taskbar customizations. Continue? [Y/N]"
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

if ($company) {
    Write-Host "Computer name starts with '$prefix' - setting up default $company accounts..."
    & "$MerionITRoot\DefaultAccounts.ps1" -Company $company
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

if (Test-Path "$MerionITRoot\secrets.psd1") {
    $confirmDelete = Read-Host "Account setup complete. Delete secrets.psd1 now? [Y/N]"
    if ($confirmDelete -ieq 'Y') {
        Remove-Item "$MerionITRoot\secrets.psd1" -Force
        Write-Host "secrets.psd1 deleted."
    } else {
        Write-Warning "secrets.psd1 left in place - remember to delete it manually once setup is fully done."
    }
}

Remove-SetupBlueprintFiles -Root $MerionITRoot
Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Set-Content -Path $CompletionMarker

$osName = (Get-ComputerInfo).OsName
if ($osName -like "*Windows 11*") {
    Write-Host "Detected Windows 11 - launching 2nd_Step..."
    Start-Process "$MerionITRoot\2nd_Step_WIN11.bat"
} elseif ($osName -like "*Windows 10*") {
    Write-Host "Detected Windows 10 - launching 3rd_Step..."
    Start-Process "$MerionITRoot\3rd_Step_WIN10.bat"
} else {
    Write-Warning "Unrecognized OS ('$osName') - launch 2nd_Step_WIN11.bat or 3rd_Step_WIN10.bat manually."
}
