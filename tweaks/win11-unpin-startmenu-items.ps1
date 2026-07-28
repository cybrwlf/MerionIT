<#
Unpins Microsoft Store and Solitaire from the Windows 11 Start Menu (does NOT uninstall either -
just unpins the tiles).

Like taskbar pinning, Windows 11 has no supported/documented API for this, and the classic
Export-StartLayout/Import-StartLayout cmdlets are broken entirely on the current redesigned Start
Menu - confirmed live 2026-07-28: even just READING the current layout with Export-StartLayout
throws "Element not found" (COMException). This uses the same undocumented InvokeVerb trick that
worked for taskbar pin detection, targeting the real AppsFolder shell item (a synthesized
shortcut instead showed a stale "Pin to Start" verb rather than "Unpin", suggesting it doesn't
track the live pinned tile). Whether "unpinfromstartscreen" actually takes effect on this build
is UNCONFIRMED as of 2026-07-28 - it completes with no error, but there's no independent way to
verify success without eyes on the actual Start Menu. Manual-Steps-Reminder.txt has a fallback
line for both apps in case this silently doesn't work, same situation as taskbar pinning.
#>

Write-Host "======================================="
Write-Host "Unpinning Microsoft Store and Solitaire from Start Menu..."
Write-Host "======================================="

$AppsFolder = (New-Object -ComObject Shell.Application).Namespace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')

foreach ($pattern in @("Microsoft Store", "*Solitaire*")) {
    $item = $AppsFolder.Items() | Where-Object { $_.Name -like $pattern } | Select-Object -First 1
    if (-not $item) {
        Write-Warning "'$pattern' not found in the Apps list - skipping."
        continue
    }
    try {
        $item.InvokeVerb("unpinfromstartscreen")
        Write-Host "Attempted unpin: $($item.Name)"
    } catch {
        Write-Warning "Failed to unpin $($item.Name): $($_.Exception.Message)"
    }
}

Write-Host "======================================="
Write-Host "Done - verify visually. See Manual-Steps-Reminder.txt for the manual fallback if this didn't take."
Write-Host "======================================="
