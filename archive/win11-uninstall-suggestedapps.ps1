# Define the path to the text file containing the suggested app names
$suggestedAppsFilePath = "C:\merionit\SuggestedAppNames.txt"

# Read the contents of the text file
$suggestedAppNames = Get-Content -Path $suggestedAppsFilePath

# Uninstall the suggested apps
foreach ($appName in $suggestedAppNames) {
    # Check if the app is installed
    if (Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue) {
        # Uninstall the app
        Remove-AppxPackage -Package "$appName" -AllUsers -Confirm:$false
    } else {
        Write-Host "App $appName is not installed."
    }
}
