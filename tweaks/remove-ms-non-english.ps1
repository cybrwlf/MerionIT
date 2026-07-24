# 1. Targeted Registry Search for Office 365 Language Packs
$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
$LanguagePacks = Get-ItemProperty $RegistryPath | Where-Object { 
    $_.DisplayName -like "*Microsoft 365*" -and 
    $_.DisplayName -match '\w{2}-\w{2}' -and 
    $_.DisplayName -notmatch 'en-us|en-gb' 
}

foreach ($Pack in $LanguagePacks) {
    Write-Host "Force Uninstalling: $($Pack.DisplayName)" -ForegroundColor Yellow
    # Extract the GUID and run the silent uninstall
    $UninstallStr = $Pack.UninstallString
    if ($UninstallStr -match '(?<={).+?(?=})') {
        $GUID = $matches[0]
        Start-Process "msiexec.exe" -ArgumentList "/x {$GUID} /qn /norestart" -Wait
    }
}

# 2. Remove OneNote/Office UWP Language Experience Packs
Write-Host "Cleaning up OneNote/UWP Language Packs..." -ForegroundColor Cyan
Get-AppxPackage -AllUsers | Where-Object { 
    $_.Name -like "*LanguageExperiencePack*" -and 
    $_.Name -notmatch 'en-US|en-GB' 
} | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

# 3. Clean up the Windows Display Language List
$LangList = Get-WinUserLanguageList
$ToRemove = $LangList | Where-Object { $_.LanguageTag -notmatch 'en-US|en-GB' }

if ($ToRemove) {
    foreach ($Lang in $ToRemove) {
        $LangList.Remove($Lang)
    }
    Set-WinUserLanguageList $LangList -Force
}