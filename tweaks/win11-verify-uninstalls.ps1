<#
Double-checks that Xbox, Dell Optimizer, and WhatsApp are actually gone after
WIN11-removebloat-appx.ps1's pass, since all three have been observed surviving that pass on real
hardware (confirmed live 2026-07-28 on MRQ7587-LT601: Microsoft.GamingApp - the modern Xbox app's
real package name, not covered by the old "Microsoft.XboxApp"/"*xbox*" patterns - and
Microsoft.XboxGameCallableUI were both still present; Dell Optimizer was still present via
Get-Package even after an EARLIER run had reported it "successfully uninstalled", likely restored
by Dell's own background services like Dell Core Services/SupportAssist).

Tries once more (in case a dependency-order issue blocked the first pass), then - instead of
silently giving up - adds a line to Manual-Steps-Reminder.txt for anything still found so the
tech doesn't need to go hunting for what didn't take.
#>

Write-Host "======================================="
Write-Host "Verifying Xbox / Dell Optimizer / WhatsApp are actually gone..."
Write-Host "======================================="

$ReminderPath = "C:\MerionIT\Manual-Steps-Reminder.txt"
function Add-ReminderIfMissing {
    # Inserts before the closing "====" banner line so dynamic reminders land inside the
    # checklist box instead of trailing after it.
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

# One more removal attempt before verifying.
Get-AppxPackage -AllUsers -Name "Microsoft.GamingApp" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers -Name "Microsoft.XboxGameCallableUI" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers -Name "*WhatsApp*" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-Package -Name "*optimizer*" -ErrorAction SilentlyContinue | Uninstall-Package -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

if ((Get-AppxPackage -AllUsers -Name "*xbox*" -ErrorAction SilentlyContinue) -or (Get-AppxPackage -AllUsers -Name "Microsoft.GamingApp" -ErrorAction SilentlyContinue)) {
    Write-Warning "Xbox-related packages still present - added to Manual-Steps-Reminder.txt."
    Add-ReminderIfMissing "[ ] Uninstall Xbox app (Settings > Apps) - automated removal didn't fully take"
}

if (Get-AppxPackage -AllUsers -Name "*WhatsApp*" -ErrorAction SilentlyContinue) {
    Write-Warning "WhatsApp still present - added to Manual-Steps-Reminder.txt."
    Add-ReminderIfMissing "[ ] Uninstall WhatsApp (Settings > Apps) - automated removal didn't fully take"
}

if (Get-Package -Name "*optimizer*" -ErrorAction SilentlyContinue) {
    Write-Warning "Dell Optimizer still present - added to Manual-Steps-Reminder.txt."
    Add-ReminderIfMissing "[ ] Uninstall Dell Optimizer (Settings > Apps) - Dell's own services may keep restoring it"
}

Write-Host "======================================="
Write-Host "Verification complete."
Write-Host "======================================="
