#Requires -RunAsAdministrator
<#
Pins Word, Excel, Outlook, Chrome, Edge, and Snipping Tool to the taskbar for the current user.

Windows 11 removed the supported/documented way to pin taskbar items programmatically - there is
no public API for it. This uses a widely-relied-on but UNDOCUMENTED workaround: invoking the
"Taskbarpin" shell verb on a real shell item.

First attempt (kept in git history, not here) invoked the verb on items enumerated through the
special AppsFolder shell namespace (shell:::{4234d49b-0245-4df3-b780-3893943456e1}) - confirmed
NOT working on this fleet's current Windows 11 build (26100.7627): it reported success for every
app with no errors, but nothing was pinned, even when run interactively at the console (ruling out
a remote-session issue). This version invokes the same verb on the app's actual shell item instead
- its real .lnk file for a normal desktop app, or a synthesized .lnk pointing at
"explorer.exe shell:AppsFolder\<AppID>" for a packaged/UWP app like Snipping Tool, which has no
real .lnk file of its own. Get-StartApps resolves the correct AppID/.lnk path for either case
without needing to guess package family names.

Since this still relies on undocumented behavior, Microsoft could break it again in a future
update. If pins silently stop appearing, suspect that first before assuming this script
regressed - verify with Get-StartApps and a manual right-click-pin test before debugging further.

Run this AFTER Install-Apps.ps1 (Chrome/Edge) and, if applicable, Fix-OfficeLanguages.ps1
(Word/Excel/Outlook) - an app that isn't installed yet is skipped with a warning, not an error,
and won't get a second chance without re-running this script.
#>

Write-Host "======================================="
Write-Host "Pinning apps to the Windows 11 taskbar..."
Write-Host "======================================="

$startApps = Get-StartApps

# Order matches the order these should appear pinned on the taskbar.
$AppsToPin = @(
    @{ FriendlyName = "Excel";         Pattern = "*Excel*" }
    @{ FriendlyName = "Word";          Pattern = "*Word*" }
    # Windows 11 ships a lightweight built-in "Outlook" app (Microsoft.OutlookForWindows) even
    # when full Office isn't installed - exclude it so this only ever pins classic desktop
    # Outlook, matching Word/Excel above.
    @{ FriendlyName = "Outlook";       Pattern = "*Outlook*"; ExcludeAppIdPattern = "*OutlookForWindows*" }
    @{ FriendlyName = "Google Chrome"; Pattern = "*Chrome*" }
    @{ FriendlyName = "Microsoft Edge";Pattern = "*Edge*" }
    @{ FriendlyName = "Snipping Tool"; Pattern = "*Snipping Tool*" }
)

$shellApp = New-Object -ComObject Shell.Application

foreach ($app in $AppsToPin) {
    $candidates = $startApps | Where-Object { $_.Name -like $app.Pattern }
    if ($app.ExcludeAppIdPattern) {
        $candidates = $candidates | Where-Object { $_.AppID -notlike $app.ExcludeAppIdPattern }
    }
    $match = $candidates | Select-Object -First 1
    if (-not $match) {
        Write-Warning "$($app.FriendlyName) not found via Get-StartApps - skipping (not installed yet?)."
        continue
    }

    if ($match.AppID -like "*.lnk") {
        # Normal desktop app - AppID is the real path to its Start Menu shortcut.
        $lnkPath = $match.AppID
    } else {
        # Packaged/UWP app (e.g. Snipping Tool) - no real .lnk file exists, so make one that
        # points at it via shell:AppsFolder, then pin that instead.
        $lnkPath = Join-Path $env:TEMP "$($app.FriendlyName -replace '[^\w]','')-pin.lnk"
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($lnkPath)
        $shortcut.TargetPath = Join-Path $env:WINDIR "explorer.exe"
        $shortcut.Arguments = "shell:AppsFolder\$($match.AppID)"
        $shortcut.Save()
    }

    try {
        $folder = $shellApp.Namespace((Split-Path $lnkPath -Parent))
        $item = $folder.ParseName((Split-Path $lnkPath -Leaf))
        $item.InvokeVerb("Taskbarpin")
        Write-Host "Pinned $($app.FriendlyName) ('$($match.Name)')."
    } catch {
        Write-Warning "Failed to pin $($app.FriendlyName): $($_.Exception.Message)"
    }
}

Write-Host "======================================="
Write-Host "Taskbar pinning complete. Verify visually - this uses an undocumented shell verb"
Write-Host "with no reliable way to confirm success from script output alone."
Write-Host "======================================="
