<#
.NOTES
	Author	:	Original by Chris Titus @christitustech, Modified by Merion IT Admin
	Version :	Beta
	Target OS: Windows 10 (latest version)

	This script clears the default pinned items from the Start Menu for the current user and
	configures settings to allow pinning new items. It uses a blank XML layout.
	Requires Administrator privileges to run.
#>

#Requires -RunAsAdministrator

Write-Host "======================================="
Write-Host "Clearing Start Menu for Windows 10..."
Write-Host "======================================="

# Define the blank Start Menu Layout XML for Windows 10
$START_MENU_LAYOUT = @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
    <LayoutOptions StartTileGroupCellWidth="6" />
    <DefaultLayoutOverride>
        <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="6" />
        </StartLayoutCollection>
    </DefaultLayoutOverride>
</LayoutModificationTemplate>
"@

$layoutFile="C:\Windows\StartMenuLayout.xml"

# Delete layout file if it already exists to ensure a fresh start
Write-Host "Checking for existing layout file..."
If (Test-Path $layoutFile) {
    Remove-Item $layoutFile -Force -ErrorAction SilentlyContinue
    Write-Host "Removed existing layout file: $layoutFile"
}

# Create the blank layout file
Write-Host "Creating blank Start Menu layout file..."
$START_MENU_LAYOUT | Out-File $layoutFile -Encoding ASCII -ErrorAction Stop
Write-Host "Layout file created successfully: $layoutFile"

$regAliases = @("HKLM", "HKCU")

# Assign the start layout and force it to apply with "LockedStartLayout" at both the machine and user level
# This ensures the new blank layout is initially enforced.
Write-Host "Applying Start Menu layout policy..."
foreach ($regAlias in $regAliases){
    $basePath = $regAlias + ":\SOFTWARE\Policies\Microsoft\Windows"
    $keyPath = $basePath + "\Explorer"
    IF(!(Test-Path -Path $keyPath)) {
        New-Item -Path $basePath -Name "Explorer" -Force | Out-Null
        Write-Host "Created registry key: $keyPath"
    }
    Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $keyPath -Name "StartLayoutFile" -Type String -Value $layoutFile -Force -ErrorAction SilentlyContinue
    Write-Host "Set LockedStartLayout and StartLayoutFile for $regAlias"
}

# Restart Explorer and attempt to open the Start Menu to load the new layout
# This is necessary for the changes to take effect immediately.
Write-Host "Restarting Explorer and opening Start Menu to apply changes..."
Stop-Process -name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -s 5 # Give Explorer time to restart
$wshell = New-Object -ComObject wscript.shell; $wshell.SendKeys('^{ESCAPE}') # Sends Ctrl+Esc to open Start Menu
Start-Sleep -s 5 # Give Start Menu time to process

# Enable the ability to pin items again by disabling "LockedStartLayout"
# After the layout is applied, this makes the Start Menu editable by the user.
Write-Host "Enabling Start Menu pinning ability..."
foreach ($regAlias in $regAliases){
    $basePath = $regAlias + ":\SOFTWARE\Policies\Microsoft\Windows"
    $keyPath = $basePath + "\Explorer"
    # Set to 0 to unlock pinning
    Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue
    Write-Host "Disabled LockedStartLayout for $regAlias"
}

# Restart Explorer again for final changes to take effect
Write-Host "Final Explorer restart for changes to apply..."
Start-Process explorer -ErrorAction SilentlyContinue

# Uncomment the next line to make clean start menu default for all new users
# This will copy the blank layout to the default user profile.
Write-Host "Attempting to import layout to default user profile (uncomment line if desired)..."
# Import-StartLayout -LayoutPath $layoutFile -MountPath $env:SystemDrive\ -ErrorAction SilentlyContinue

# Clean up the temporary layout file
Write-Host "Cleaning up temporary layout file..."
Remove-Item $layoutFile -Force -ErrorAction SilentlyContinue
Write-Host "Script execution complete for Windows 10."
