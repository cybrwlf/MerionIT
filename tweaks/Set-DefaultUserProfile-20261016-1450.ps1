#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Makes accounts created AFTER setup start with the per-user settings setup gave the setup account.

.DESCRIPTION
    Most tweaks in setup write to HKEY_CURRENT_USER, so they only ever reached the account that ran
    setup (pcsadmin). Every account added later was built from the Default profile and started with
    plain Windows defaults: Explorer without "expand to open folder", extra taskbar buttons, tips and
    suggestions on. See research\default-user-profile-tweaks.md for the full story.

    This writes those same values into the Default user hive (C:\Users\Default\NTUSER.DAT), so any
    profile created afterwards inherits them at first logon. It also writes a taskbar pin layout for
    new profiles, and a one-time checklist that opens in Notepad at a new profile's first sign-in.
    It does NOT change profiles that already exist (unless -UserName is given).

    What it does, in order:
      1. Backs up the hive it is about to edit (newest 5 kept) to -BackupDir.
      2. Loads the hive, writes every value that differs, reads each one back and compares type and data.
      3. Unloads the hive and CHECKS it unloaded. A hive left mounted keeps NTUSER.DAT locked.
      4. (Default profile only) writes the taskbar layout and reads it back.

    Safe to run again: values already correct are left alone and reported as such.

    Left out on purpose
      - HideAppList / HideRecentlyAddedApps (HKCU policy that WIN11-ClearStartMenu.ps1 sets): it hides
        the "All apps" list, which is a side effect on the setup account, not something users should get.
      - The classic right-click menu: its key lives in the classes hive, the Default profile has none,
        and the machine-wide key is already present.
      - Everything under HKLM (widgets, Start policies, Location) is machine-wide and already applies
        to every user.
      - Values whose type setup sets inconsistently are written with the type the setup account
        actually has (screensaver timeout is a DWord, ScreenSaveActive a String).

.PARAMETER UserName
    Apply the same values to this EXISTING local account instead of the Default profile. The account
    must be signed out. Use for an account that was created before this script existed.

.PARAMETER ReportOnly
    Load the hive, compare, change nothing. (Loading and unloading the hive is the only thing touched.)

.PARAMETER SkipTaskbarLayout
    Seed registry values only.

.PARAMETER PinPlacement
    Replace (default): the pin list is exactly File Explorer, Edge, Chrome, Word, Excel, Outlook (classic) and
    Outlook (new) and Snipping Tool, so the Microsoft Store pin is dropped. Add: keep Windows' own default pins and append
    Chrome, Word, Excel, the two Outlooks and Snipping Tool.

.PARAMETER LayoutMethod
    DefaultProfile (default): merge a CustomTaskbarLayoutCollection into
    C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml.
    OemPath: write C:\Windows\OEM\TaskbarLayoutModification.xml and set HKLM ...\Explorer\LayoutXMLPath.
    Only needed if the first does not take on a build (test with a throwaway account).

.NOTES
    Writes with Write-Output (Kaseya runs as SYSTEM, Write-Host output can be lost).
    Exit code: 0 = everything written and verified
               2 = a value, the layout or the hive unload could not be verified
#>
[CmdletBinding()]
param(
    [string]$UserName,
    [switch]$ReportOnly,
    [switch]$SkipTaskbarLayout,
    [ValidateSet('Replace', 'Add')]
    [string]$PinPlacement = 'Replace',
    [ValidateSet('DefaultProfile', 'OemPath')]
    [string]$LayoutMethod = 'DefaultProfile',
    [string]$BackupDir = 'C:\MerionIT\backup\default-profile'
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2026-10-16.5'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$problems = 0

function Say($m) { Write-Output $m }

# Local admins run with a filtered token at logon, so a file only Administrators can read is unreadable to
# them too (what stopped BGInfo, 2026-10-15). True if Users, Authenticated Users or Everyone can read it.
function Test-UsersCanRead([string]$Path) {
    $readers = 'S-1-5-32-545', 'S-1-5-11', 'S-1-1-0'
    foreach ($ace in (Get-Acl -LiteralPath $Path).Access) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        try { $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
        if (($readers -contains $sid) -and ($ace.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadData)) { return $true }
    }
    $false
}

# ---- The settings -------------------------------------------------------------------------------
# Taken from basic10-11stuff.ps1 (HKCU part), WIN11-ClearStartMenu.ps1, TurnOFFgetevenmoreoutofwindows.ps1,
# win11-remove-teamschaticon.ps1, win11-startmenu-left.ps1, win11-search-highlights-off.ps1 and
# win11-screensaver.ps1. Types match what the setup account actually has.
$Settings = New-Object System.Collections.Generic.List[object]
function Add-Setting([string]$Path, [string]$Name, [string]$Kind, $Value, [bool]$Optional = $false) {
    $Settings.Add([pscustomobject]@{ Path = $Path; Name = $Name; Kind = $Kind; Value = $Value; Optional = $Optional })
}

$cv = 'Software\Microsoft\Windows\CurrentVersion'

# Explorer and taskbar
$adv = "$cv\Explorer\Advanced"
foreach ($n in 'ShowTaskViewButton', 'ShowCortanaButton', 'ShowCopilotButton', 'ListviewAlphaSelect',
               'ListviewShadow', 'TaskbarAnimations', 'TaskbarAl', 'TaskbarMn', 'HideFileExt') {
    Add-Setting $adv $n DWord 0
}
foreach ($n in 'LaunchTo', 'NavPaneShowAllFolders', 'NavPaneExpandToCurrentFolder', 'Start_Layout') {
    Add-Setting $adv $n DWord 1
}
# Widgets button. Windows refuses this write on some builds ("unauthorized operation", also seen in
# win11-startmenu-left.ps1). Optional: reported, never fails the run. The machine-wide policy
# HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests = 0 (win11-Disable-Taskbar-Widgets.ps1) already
# disables widgets for every user.
Add-Setting $adv 'TaskbarDa' DWord 0 $true
Add-Setting "$adv\People" 'PeopleBand' DWord 0
Add-Setting "$cv\Explorer\OperationStatusManager" 'EnthusiastMode' DWord 1
Add-Setting "$cv\Explorer\VisualEffects" 'VisualFXSetting' DWord 3
Add-Setting 'Software\Microsoft\Windows\DWM' 'EnableAeroPeek' DWord 0

# Search box: mode 2 is the box (win11-startmenu-left.ps1); highlights off; no Bing in the box
Add-Setting "$cv\Search" 'SearchboxTaskbarMode' DWord 2
Add-Setting "$cv\Search" 'BingSearchEnabled' DWord 0
Add-Setting "$cv\SearchSettings" 'IsDynamicSearchBoxEnabled' DWord 0

# Tips, suggestions and silently installed apps off
$cdm = "$cv\ContentDeliveryManager"
foreach ($n in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
               'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled',
               'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
               'SubscribedContent-338389Enabled', 'SubscribedContent-353698Enabled',
               'SubscribedContent-310093Enabled') {
    Add-Setting $cdm $n DWord 0
}
Add-Setting "$cv\UserProfileEngagement" 'ScoobeSystemSettingEnabled' DWord 0

# Notifications, feedback, telemetry-ish, Meet Now
Add-Setting "$cv\PushNotifications" 'ToastEnabled' DWord 0
Add-Setting 'Software\Policies\Microsoft\Windows\Explorer' 'DisableNotificationCenter' DWord 0
Add-Setting 'Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' DWord 0
Add-Setting 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' DWord 1
Add-Setting "$cv\Policies\Explorer" 'HideSCAMeetNow' DWord 1

# Game bar / DVR off
$gcs = 'System\GameConfigStore'
Add-Setting $gcs 'GameDVR_DXGIHonorFSEWindowsCompatible' DWord 1
Add-Setting $gcs 'GameDVR_HonorUserFSEBehaviorMode' DWord 1
Add-Setting $gcs 'GameDVR_EFSEFeatureFlags' DWord 0
Add-Setting $gcs 'GameDVR_Enabled' DWord 0
Add-Setting $gcs 'GameDVR_FSEBehavior' DWord 2

# Responsiveness and screensaver
$cpd = 'Control Panel\Desktop'
Add-Setting $cpd 'MenuShowDelay' String '200'
Add-Setting $cpd 'AutoEndTasks' DWord 1
Add-Setting $cpd 'DragFullWindows' String '0'
Add-Setting $cpd 'UserPreferencesMask' Binary ([byte[]](144, 18, 3, 128, 16, 0, 0, 0))
Add-Setting "$cpd\WindowMetrics" 'MinAnimate' String '0'
Add-Setting 'Control Panel\Mouse' 'MouseHoverTime' DWord 400
Add-Setting 'Control Panel\Keyboard' 'KeyboardDelay' DWord 0
Add-Setting $cpd 'ScreenSaveActive' String '1'
Add-Setting $cpd 'SCRNSAVE.EXE' String 'Ribbons.scr'
Add-Setting $cpd 'ScreenSaveTimeOut' DWord 300

# Outlook: no bottom navigation bar
Add-Setting 'Software\Microsoft\Office\16.0\Common\ExperimentEcs\Overrides' 'Microsoft.Office.Outlook.Hub.HubBar' String 'false'

# Marker, so a profile can be told apart from one built before this existed
Add-Setting 'Software\MerionIT' 'DefaultSeedVersion' String $ScriptVersion

# Checklist for the tech: Notepad opens manual\New-User-Reminder.txt ONCE, at the new profile's first
# sign-in (RunOnce in the Default hive is copied into every new profile and consumed there). That is
# when the tech is at the desk. Not set for an existing profile (-UserName), and skipped with a note
# if the file is not on this machine, because Notepad would otherwise ask to create it.
$reminderFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'manual\New-User-Reminder.txt'
if ($UserName) {
    # existing profile: no first-sign-in checklist
} elseif (Test-Path -LiteralPath $reminderFile) {
    if (Test-UsersCanRead $reminderFile) {
    
    Add-Setting "$cv\RunOnce" 'MerionITNewUserChecklist' String ('notepad.exe "' + $reminderFile + '"')
    } else {
        Say "Checklist: ordinary users cannot read $reminderFile (local admins run with a filtered token), so Notepad would show a permission error at first sign-in. Not set. Give Users read access to that folder, then run this again."
    }
} else {
    Say "Checklist: $reminderFile not found, so no checklist will open at a new user's first sign-in. Run Update-Scripts.bat."
}

# ---- Registry helpers ---------------------------------------------------------------------------
function Test-Same($setting, $actual, $actualKind) {
    if ($null -eq $actual) { return $false }
    if ("$actualKind" -ne $setting.Kind) { return $false }
    switch ($setting.Kind) {
        'Binary' { return (($actual -join ',') -eq ($setting.Value -join ',')) }
        'DWord'  { return ([int]$actual -eq [int]$setting.Value) }
        default  { return ([string]$actual -ceq [string]$setting.Value) }
    }
}

function Read-One($Root, $setting) {
    $k = [Microsoft.Win32.Registry]::Users.OpenSubKey("$Root\$($setting.Path)")
    $v = $null; $kind = $null
    if ($k) {
        $v = $k.GetValue($setting.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -ne $v) { $kind = $k.GetValueKind($setting.Name) }
        $k.Close()
    }
    [pscustomobject]@{ Value = $v; Kind = $kind }
}

function Sync-HiveValues([string]$Root, [bool]$Write) {
    $r = [pscustomobject]@{ Same = 0; Changed = 0; Wrong = New-Object System.Collections.Generic.List[string]; Blocked = New-Object System.Collections.Generic.List[string] }
    foreach ($s in $Settings) {
        $cur = Read-One $Root $s
        if (Test-Same $s $cur.Value $cur.Kind) { $r.Same++; continue }
        if (-not $Write) { if ($s.Optional) { $r.Blocked.Add("$($s.Path)\$($s.Name)   [not set; Windows may refuse]") } else { $r.Wrong.Add("$($s.Path)\$($s.Name)") }; continue }
        # One value Windows refuses to write must not stop the rest: record it with the reason, carry on.
        try {
            $wk = [Microsoft.Win32.Registry]::Users.CreateSubKey("$Root\$($s.Path)")
            try { $wk.SetValue($s.Name, $s.Value, [Microsoft.Win32.RegistryValueKind]$s.Kind) } finally { $wk.Close() }
        } catch {
            $why = $_.Exception.Message
            if ($_.Exception.InnerException) { $why = $_.Exception.InnerException.Message }
            if ($s.Optional) { $r.Blocked.Add("$($s.Path)\$($s.Name)   [$why]") } else { $r.Wrong.Add("$($s.Path)\$($s.Name)   [$why]") }
            continue
        }
        $after = Read-One $Root $s
        if (Test-Same $s $after.Value $after.Kind) { $r.Changed++ } elseif ($s.Optional) { $r.Blocked.Add("$($s.Path)\$($s.Name)") } else { $r.Wrong.Add("$($s.Path)\$($s.Name)") }
    }
    $r
}

function Mount-Hive([string]$File, [string]$Name) {
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
    & reg.exe load "HKU\$Name" $File 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "reg load failed for $File (is the profile in use?)" }
}

# PowerShell's registry provider and our own key objects can hold handles; the unload fails until
# they are collected. A failed unload leaves NTUSER.DAT locked, so it is retried and then CHECKED.
function Dismount-Hive([string]$Name) {
    $ErrorActionPreference = 'Continue'
    for ($i = 0; $i -lt 6; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        & reg.exe unload "HKU\$Name" 2>&1 | Out-Null
        if (-not (Test-Path "Registry::HKEY_USERS\$Name")) { return $true }
        Start-Sleep -Milliseconds 800
    }
    $false
}

# ---- Which hive -----------------------------------------------------------------------------------
$target = 'Default'
$hiveFile = 'C:\Users\Default\NTUSER.DAT'
if ($UserName) {
    $acct = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if (-not $acct) { throw "No local account named '$UserName'." }
    $prof = Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $acct.SID.Value }
    if (-not $prof) { throw "'$UserName' has no profile yet. Run without -UserName to seed the Default profile instead." }
    if ($prof.Loaded) { throw "'$UserName' is signed in (profile loaded). Sign them out first. Nothing was changed." }
    $target = $UserName
    $hiveFile = Join-Path $prof.LocalPath 'NTUSER.DAT'
}
if (-not (Test-Path -LiteralPath $hiveFile -PathType Leaf)) { throw "Hive not found: $hiveFile" }

Say "Set-DefaultUserProfile $ScriptVersion on $env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Say "Target  : $target  ($hiveFile)"
Say "Mode    : $(if ($ReportOnly) { 'REPORT ONLY - no values are changed' } else { 'apply' })"

# ---- Back up, then edit the hive --------------------------------------------------------------------
$mount = "MerionSeed_$PID"
# Look first. Backups are rotated (newest 5), so a run that changes nothing must not take one, or a few
# harmless repeat runs would push the pre-change backup out.
$needWrite = $false
if (-not $ReportOnly) {
    Mount-Hive $hiveFile $mount
    try { $needWrite = ((Sync-HiveValues $mount $false).Wrong.Count -gt 0) }
    finally {
        if (-not (Dismount-Hive $mount)) {
            $problems++
            Say "ERROR   : the hive HKU\$mount did not unload. Run 'reg unload HKU\$mount' (or reboot) before anyone signs in for the first time."
        }
    }
}
if ((-not $ReportOnly) -and $needWrite) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $bak = Join-Path $BackupDir "$target-NTUSER.DAT.$stamp.bak"
    Copy-Item -LiteralPath $hiveFile -Destination $bak -Force
    Say "Backup  : $bak"
    Get-ChildItem -LiteralPath $BackupDir -Filter "$target-NTUSER.DAT.*.bak" -File |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
}

$res = $null
Mount-Hive $hiveFile $mount
try {
    $res = Sync-HiveValues $mount ((-not $ReportOnly) -and $needWrite)
} finally {
    if (-not (Dismount-Hive $mount)) {
        $problems++
        Say "ERROR   : the hive HKU\$mount did not unload. Run 'reg unload HKU\$mount' (or reboot) before anyone signs in for the first time."
    }
}
Say ''
Say "--- VALUES ($($Settings.Count) defined) ---"
Say "Already correct : $($res.Same)"
if ($ReportOnly) {
    Say "Would change    : $($res.Wrong.Count)"
} else {
    Say "Written+verified: $($res.Changed)"
    Say "NOT verified    : $($res.Wrong.Count)"
}
foreach ($w in $res.Wrong) { Say "   $w" }
foreach ($b in $res.Blocked) { Say "Optional, not set (the machine-wide widgets policy covers it): $b" }
if (-not $ReportOnly) { $problems += $res.Wrong.Count }

# ---- Taskbar pins for new profiles ------------------------------------------------------------------
$layoutState = 'skipped'
if ($SkipTaskbarLayout -or $UserName) {
    if ($UserName) { Say ''; Say 'Taskbar layout: not applied to an existing profile (it only takes effect at first logon).' }
} else {
    $nsLM = 'http://schemas.microsoft.com/Start/2014/LayoutModification'
    $nsDL = 'http://schemas.microsoft.com/Start/2014/FullDefaultLayout'
    $nsTB = 'http://schemas.microsoft.com/Start/2014/TaskbarLayout'
    $nsST = 'http://schemas.microsoft.com/Start/2014/StartLayout'

    # Order here is the order on the taskbar. Default = a pin Windows already puts there.
    $allPins = @(
        @{ Name = 'File Explorer';     Type = 'DesktopApp'; Attr = 'DesktopApplicationID';       Value = 'Microsoft.Windows.Explorer'; Default = $true },
        @{ Name = 'Microsoft Edge';    Type = 'DesktopApp'; Attr = 'DesktopApplicationID';       Value = 'MSEdge';                     Default = $true },
        @{ Name = 'Google Chrome';     Type = 'DesktopApp'; Attr = 'DesktopApplicationLinkPath'; Value = '%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk' },
        @{ Name = 'Word';              Type = 'DesktopApp'; Attr = 'DesktopApplicationLinkPath'; Value = '%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Word.lnk' },
        @{ Name = 'Excel';             Type = 'DesktopApp'; Attr = 'DesktopApplicationLinkPath'; Value = '%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Excel.lnk' },
        @{ Name = 'Outlook (classic)'; Type = 'DesktopApp'; Attr = 'DesktopApplicationLinkPath'; Value = '%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Outlook (classic).lnk' },
        @{ Name = 'Outlook (new)';     Type = 'UWA';        Attr = 'AppUserModelID';             Value = 'Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows'; Package = 'Microsoft.OutlookForWindows' },
        @{ Name = 'Snipping Tool';     Type = 'UWA';        Attr = 'AppUserModelID';             Value = 'Microsoft.ScreenSketch_8wekyb3d8bbwe!App'; Package = 'Microsoft.ScreenSketch' }
    )

    $pins = @()
    foreach ($p in $allPins) {
        if ($PinPlacement -eq 'Add' -and $p.Default) { continue }
        if ($p.Attr -eq 'DesktopApplicationLinkPath' -and -not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($p.Value)))) {
            Say "Taskbar layout: $($p.Name) not pinned, its shortcut is not on this machine."
            continue
        }
        if ($p.Package -and -not (Get-AppxPackage -AllUsers -Name $p.Package -ErrorAction SilentlyContinue)) {
            Say "Taskbar layout: $($p.Name) not pinned, the app is not installed."
            continue
        }
        $pins += $p
    }

    function New-LayoutDocument([string]$ExistingFile) {
        $doc = New-Object System.Xml.XmlDocument
        $doc.PreserveWhitespace = $false
        if ($ExistingFile -and (Test-Path -LiteralPath $ExistingFile)) {
            $doc.Load($ExistingFile)
            $root = $doc.DocumentElement
        } else {
            $root = $doc.CreateElement('LayoutModificationTemplate', $nsLM)
            $root.SetAttribute('Version', '1')
            [void]$doc.AppendChild($root)
        }
        # Namespace declarations the taskbar section needs; the Start section already has its own.
        foreach ($d in @(@('xmlns:defaultlayout', $nsDL), @('xmlns:start', $nsST), @('xmlns:taskbar', $nsTB))) {
            if (-not $root.HasAttribute($d[0])) { $root.SetAttribute($d[0], $d[1]) }
        }
        foreach ($old in @($root.ChildNodes | Where-Object { $_.LocalName -eq 'CustomTaskbarLayoutCollection' })) {
            [void]$root.RemoveChild($old)
        }
        $coll = $doc.CreateElement('CustomTaskbarLayoutCollection', $nsLM)
        if ($PinPlacement -eq 'Replace') { $coll.SetAttribute('PinListPlacement', 'Replace') }
        $layout = $doc.CreateElement('defaultlayout', 'TaskbarLayout', $nsDL)
        $list = $doc.CreateElement('taskbar', 'TaskbarPinList', $nsTB)
        foreach ($p in $pins) {
            $e = $doc.CreateElement('taskbar', $p.Type, $nsTB)
            $e.SetAttribute($p.Attr, $p.Value)
            [void]$list.AppendChild($e)
        }
        [void]$layout.AppendChild($list)
        [void]$coll.AppendChild($layout)
        [void]$root.AppendChild($coll)
        $doc
    }

    function Save-LayoutDocument($Doc, [string]$Path) {
        $ws = New-Object System.Xml.XmlWriterSettings
        $ws.Indent = $true
        $ws.Encoding = New-Object System.Text.UTF8Encoding($false)
        $w = [System.Xml.XmlWriter]::Create($Path, $ws)
        try { $Doc.Save($w) } finally { $w.Close() }
    }

    function Read-LayoutPins([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $d = New-Object System.Xml.XmlDocument
        try { $d.Load($Path) } catch { return $null }
        $c = $d.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'CustomTaskbarLayoutCollection' } | Select-Object -First 1
        if (-not $c) { return , @('') }   # file is valid but has no taskbar section: empty placement, no pins
        $placement = $c.GetAttribute('PinListPlacement')
        $items = @($c.GetElementsByTagName('*') | Where-Object { $_.LocalName -in 'DesktopApp', 'UWA' } | ForEach-Object {
            if ($_.HasAttribute('DesktopApplicationID')) { $_.GetAttribute('DesktopApplicationID') }
            elseif ($_.HasAttribute('DesktopApplicationLinkPath')) { Split-Path $_.GetAttribute('DesktopApplicationLinkPath') -Leaf }
            else { $_.GetAttribute('AppUserModelID') }
        })
        ,@(@($placement) + $items)
    }

    if ($LayoutMethod -eq 'DefaultProfile') {
        $layoutFile = 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml'
        $existing = $layoutFile
    } else {
        $layoutFile = 'C:\Windows\OEM\TaskbarLayoutModification.xml'
        $existing = $null
    }
    $want = @($pins | ForEach-Object { if ($_.Attr -eq 'DesktopApplicationLinkPath') { Split-Path $_.Value -Leaf } else { $_.Value } })
    $placementWant = if ($PinPlacement -eq 'Replace') { 'Replace' } else { '' }

    Say ''
    Say "--- TASKBAR LAYOUT ($LayoutMethod, placement $PinPlacement) ---"
    Say "File    : $layoutFile"
    if (-not $ReportOnly) {
        New-Item -ItemType Directory -Path (Split-Path $layoutFile -Parent) -Force | Out-Null
        $doc = New-LayoutDocument $existing
        $tmp = [IO.Path]::GetTempFileName()
        Save-LayoutDocument $doc $tmp
        $changed = (-not (Test-Path -LiteralPath $layoutFile)) -or ((Get-FileHash $tmp -Algorithm SHA256).Hash -ne (Get-FileHash $layoutFile -Algorithm SHA256).Hash)
        if ($changed) {
            if (Test-Path -LiteralPath $layoutFile) {
                New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
                Copy-Item -LiteralPath $layoutFile -Destination (Join-Path $BackupDir "$(Split-Path $layoutFile -Leaf).$stamp.bak") -Force
            }
            Copy-Item -LiteralPath $tmp -Destination $layoutFile -Force
        } else {
            Say 'Layout  : file already matches, left alone.'
        }
        Remove-Item -LiteralPath $tmp -Force
        if ($LayoutMethod -eq 'OemPath') {
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'LayoutXMLPath' -Value $layoutFile -Type String
        }
    }
    $got = Read-LayoutPins $layoutFile
    if ($null -eq $got) {
        $layoutState = 'missing'
        Say 'Layout  : not present or not valid XML.'
        if (-not $ReportOnly) { $problems++ }
    } else {
        $gotPlacement = $got[0]; $gotPins = @($got | Select-Object -Skip 1)
        $same = ($gotPlacement -eq $placementWant) -and (($gotPins -join '|') -eq ($want -join '|'))
        $layoutState = if ($same) { 'ok' } else { 'differs' }
        Say "Placement: $(if ($gotPlacement) { $gotPlacement } else { 'Add (default)' })"
        Say "Pins     : $($gotPins -join ', ')"
        if (-not $same -and -not $ReportOnly) { $problems++; Say 'ERROR   : the file on disk does not match what was written.' }
        if (-not $same -and $ReportOnly) { Say 'Differs from what this script would write.' }
        if ($LayoutMethod -eq 'OemPath') {
            Say "LayoutXMLPath: $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -ErrorAction SilentlyContinue).LayoutXMLPath)"
        }
    }
    Say 'Note    : pins apply when a NEW profile signs in for the first time. Accounts that already exist keep their taskbar.'
}

Say ''
$mode = if ($ReportOnly) { 'report' } else { 'apply' }
Say "RESULT|$env:COMPUTERNAME|target=$target|values=$($Settings.Count)|same=$($res.Same)|changed=$($res.Changed)|notverified=$($res.Wrong.Count)|optionalskipped=$($res.Blocked.Count)|layout=$layoutState|problems=$problems|mode=$mode|v=$ScriptVersion"
if ($problems -gt 0) { exit 2 }
exit 0
