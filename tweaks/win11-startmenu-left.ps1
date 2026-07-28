$KeyPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$ValueData = 0

# TaskbarDa/TaskbarMn have been observed throwing UnauthorizedAccessException on some machines
# even with confirmed FullControl on $KeyPath (reproduced live 2026-07-28 on MRQ7587-LT601) -
# root cause still unclear (possibly a live shell policy reconciliation, not a real ACL problem).
# Wrapping each value in its own try/catch so one failing here can't stop TaskbarAl or the search
# box fix below from applying - that's what was actually happening before this fix: the
# unhandled error on TaskbarDa was silently cutting the rest of this script short every time.
foreach ($ValueName in @("TaskbarAl", "TaskbarDa", "TaskbarMn")) {
    try {
        Set-ItemProperty -Path $KeyPath -Name $ValueName -Value $ValueData -Type DWORD -Force -ErrorAction Stop
    } catch {
        Write-Warning "Could not set $ValueName : $($_.Exception.Message)"
    }
}

# Modify the registry value to show the search box
try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 2 -Type DWord -Force -ErrorAction Stop
} catch {
    Write-Warning "Could not set SearchboxTaskbarMode: $($_.Exception.Message)"
}
