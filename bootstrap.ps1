<#
Entry point. Usage from an admin PowerShell prompt on a fresh Win10/11 machine:

  powershell.exe -ExecutionPolicy Unrestricted -Command "irm https://raw.githubusercontent.com/cybrwlf/MerionIT/master/bootstrap.ps1 | iex"

Syncs the repo into C:\MerionIT and launches 1st_Step.ps1. This is safe to re-run on an
already-set-up machine (e.g. to pick up a newer version of the scripts) - it only ever touches
files that are actually part of this repo. It tracks exactly which files it placed on disk
(.repo-manifest.txt) and removes only those that no longer exist in the newer version being
synced - it never touches InstallLog.csv, the backup\ folder that backup-userfiles.ps1 writes
real user data into, or anything else not tracked by the repo.

Full console output is transcribed to C:\MerionIT\logs\bootstrap-<timestamp>.log.

-NoLaunch syncs the files and stops there. Use it when you're driving setup remotely and want to
call 1st_Step.ps1 yourself with explicit parameters (e.g. -ForceRename for a reassignment),
rather than having it start the default interactive pipeline the instant the sync lands.
#>
param(
    [switch]$NoLaunch
)

$RepoZipUrl = "https://github.com/cybrwlf/MerionIT/archive/refs/heads/master.zip"
$Dest = "C:\MerionIT"
$ZipPath = "$env:TEMP\MerionIT.zip"
$ExtractPath = "$env:TEMP\MerionIT-extract"
$ManifestPath = Join-Path $Dest ".repo-manifest.txt"

if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Path $Dest | Out-Null
}
$LogDir = Join-Path $Dest "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "bootstrap-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log") | Out-Null

Write-Host "Downloading MerionIT from GitHub..."
try {
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $ZipPath -ErrorAction Stop
} catch {
    throw "Download failed ($($_.Exception.Message)) - check that $RepoZipUrl is reachable and points at a real branch."
}

if (Test-Path $ExtractPath) { Remove-Item $ExtractPath -Recurse -Force }
Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
$extractedFolder = Get-ChildItem -Path $ExtractPath -Directory | Select-Object -First 1
if (-not $extractedFolder) {
    throw "Extraction produced no folder - the downloaded zip may be empty or invalid. Aborting before touching $Dest."
}

# Repo-only files that serve no purpose on an actual machine - never synced to $Dest. Removing a
# name from here also makes the NEXT bootstrap run clean up any stale copy already on disk (it's
# just an ordinary manifest-tracked file at that point).
$ExcludeFromSync = @("secrets.template.psd1", "README.md", ".gitattributes", ".gitignore")
# Whole folders excluded the same way - currently just archive/, which holds dead/retired scripts
# kept for reference (see archive/archive-summary.md). Never lands on a machine, day one or ever.
$ExcludeFoldersFromSync = @("archive")

$oldManifest = if (Test-Path $ManifestPath) { @(Get-Content $ManifestPath) } else { @() }
$newFiles = @(Get-ChildItem -Path $extractedFolder.FullName -Recurse -File | ForEach-Object {
    $_.FullName.Substring($extractedFolder.FullName.Length + 1)
} | Where-Object {
    $rel = $_
    ($ExcludeFromSync -notcontains $rel) -and
    (-not ($ExcludeFoldersFromSync | Where-Object { $rel -like "$_\*" }))
})

# Remove files that this repo used to ship but no longer does (renamed/deleted scripts from an
# older pull) - only ever files that were in a previous manifest, never anything else on disk.
$toRemove = $oldManifest | Where-Object { $newFiles -notcontains $_ }
foreach ($rel in $toRemove) {
    $target = Join-Path $Dest $rel
    if (Test-Path $target) {
        Remove-Item $target -Force
        Write-Host "Removed stale file from a previous version: $rel"
    }
}

# Copy the current version's files in
foreach ($rel in $newFiles) {
    $src = Join-Path $extractedFolder.FullName $rel
    $dstFile = Join-Path $Dest $rel
    $dstDir = Split-Path $dstFile -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -Path $src -Destination $dstFile -Force
}

# Clean up any now-empty directories left behind by removed files
Get-ChildItem -Path $Dest -Recurse -Directory -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName -Descending |
    Where-Object { (Get-ChildItem -Path $_.FullName -Force | Measure-Object).Count -eq 0 } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$newFiles | Set-Content -Path $ManifestPath

Remove-Item $ZipPath -Force
Remove-Item $ExtractPath -Recurse -Force

Write-Host "MerionIT synced to $Dest."

if ($NoLaunch) {
    Write-Host "-NoLaunch specified - stopping here. Run $Dest\1st_Step.ps1 yourself when ready."
    Stop-Transcript | Out-Null
    return
}

Write-Host "Launching setup..."
Stop-Transcript | Out-Null
& "$Dest\1st_Step.ps1"
