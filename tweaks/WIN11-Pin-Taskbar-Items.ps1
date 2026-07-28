#Requires -RunAsAdministrator
<#
Pins Word, Excel, Outlook, Chrome, Edge, and Snipping Tool to the taskbar for the current user.

Windows 11 removed the supported/documented way to pin taskbar items programmatically - there is
no public API for it. This uses a widely-relied-on but UNDOCUMENTED workaround: invoking the
"Taskbarpin" shell verb directly on items enumerated through the special AppsFolder shell
namespace (shell:::{4234d49b-0245-4df3-b780-3893943456e1}). That verb still works there via
InvokeVerb even on builds where it no longer shows up in a normal right-click menu or in
.Verbs() enumeration - so this calls InvokeVerb directly rather than checking for the verb first.

Since this relies on undocumented behavior, Microsoft could break it in a future update. If
pins silently stop appearing after a Windows update, suspect that first before assuming this
script regressed. Run this AFTER Install-Apps.ps1 (Chrome/Edge) and, if applicable,
Fix-OfficeLanguages.ps1 (Word/Excel/Outlook) - an app that isn't installed yet is skipped with
a warning, not an error, and won't get a second chance without re-running this script.
#>

Write-Host "======================================="
Write-Host "Pinning apps to the Windows 11 taskbar..."
Write-Host "======================================="

$AppsFolder = (New-Object -ComObject Shell.Application).Namespace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
$allItems = $AppsFolder.Items()

# Order matches the order these should appear pinned on the taskbar.
$AppsToPin = @(
    @{ FriendlyName = "Excel";         Pattern = "*Excel*" }
    @{ FriendlyName = "Word";          Pattern = "*Word*" }
    # Windows 11 ships a lightweight built-in "Outlook" app (Microsoft.OutlookForWindows) even
    # when full Office isn't installed - exclude it so this only ever pins classic desktop
    # Outlook, matching Word/Excel above.
    @{ FriendlyName = "Outlook";       Pattern = "*Outlook*"; ExcludePathPattern = "*OutlookForWindows*" }
    @{ FriendlyName = "Google Chrome"; Pattern = "*Chrome*" }
    @{ FriendlyName = "Microsoft Edge";Pattern = "*Edge*" }
    @{ FriendlyName = "Snipping Tool"; Pattern = "*Snipping Tool*" }
)

foreach ($app in $AppsToPin) {
    $matches = $allItems | Where-Object { $_.Name -like $app.Pattern }
    if ($app.ExcludePathPattern) {
        $matches = $matches | Where-Object { $_.Path -notlike $app.ExcludePathPattern }
    }
    $item = $matches | Select-Object -First 1
    if (-not $item) {
        Write-Warning "$($app.FriendlyName) not found in the Apps list - skipping (not installed yet?)."
        continue
    }
    try {
        $item.InvokeVerb("Taskbarpin")
        Write-Host "Pinned $($app.FriendlyName) ('$($item.Name)')."
    } catch {
        Write-Warning "Failed to pin $($app.FriendlyName): $($_.Exception.Message)"
    }
}

Write-Host "======================================="
Write-Host "Taskbar pinning complete. Verify visually - this uses an undocumented shell verb"
Write-Host "with no reliable way to confirm success from script output alone."
Write-Host "======================================="
