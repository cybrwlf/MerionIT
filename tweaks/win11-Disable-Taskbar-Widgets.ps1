#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Turns off Widgets (the taskbar weather/news button) for every user on Windows 11.

.DESCRIPTION
    Sets the machine policy HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests = 0
    ("Allow widgets" = Disabled), then reads it back.

    Why it is not a plain registry write any more (2026-11-16): on newer Windows 11 builds Windows
    blocks that one value. On MRQ3049-LT601 (Win11 Pro 26H2, build 26300) Set-ItemProperty failed with
    "Attempted to perform an unauthorized operation" while a test value in the same key wrote fine, and
    the old script only logged the error, so every build there kept Widgets. Likely cause: the UCPD
    driver, which also blocks the per-user TaskbarDa value.

    What it does:
      1. Already 0: nothing to do.
      2. Tries the direct write (still works on older builds), reads it back.
      3. If Windows refused it: adds the same setting to the LOCAL Group Policy file
         (C:\Windows\System32\GroupPolicy\Machine\Registry.pol), keeping every entry already in it,
         bumps gpt.ini so Windows sees a change, runs gpupdate. The Group Policy service then writes the
         value. Both files are backed up first to C:\MerionIT\backup\gpo-<time>.
      4. Reads the value back. Exit 0 = Widgets policy is 0, 2 = it is not.

    Tested 2026-11-16 on MRQ3049-LT601: value landed, brand-new profiles had no Widgets button.
    Being a policy, it may show "Some of these settings are managed by your organization" on
    Settings > Personalization > Taskbar. It does not touch the Windows Update page.

.NOTES
    Write-Output only (Kaseya runs as SYSTEM). ASCII only (Windows PowerShell 5.1).
    A domain Group Policy, if a machine ever gets one, overrides the local one.
#>

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2026-11-16.1'
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
$polKey = 'Software\Policies\Microsoft\Dsh'
$name = 'AllowNewsAndInterests'

function Get-WidgetsValue { (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name }

Write-Output '======================================='
Write-Output "Disabling Windows 11 Widgets (v$ScriptVersion)..."
Write-Output '======================================='

if ((Get-WidgetsValue) -eq 0) {
    Write-Output "Already set: $name = 0. Nothing to do."
    exit 0
}

# --- 1. Direct write (works on older builds)
try {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name $name -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
} catch {
    Write-Output "Direct write refused by Windows ($($_.Exception.Message)). Using local Group Policy instead."
}
if ((Get-WidgetsValue) -eq 0) {
    Write-Output "Set directly: $name = 0."
    exit 0
}

# --- 2. Local Group Policy
$gp = Join-Path $env:SystemRoot 'System32\GroupPolicy'
$pol = Join-Path $gp 'Machine\Registry.pol'
$ini = Join-Path $gp 'gpt.ini'
$bk = "C:\MerionIT\backup\gpo-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $bk -Force | Out-Null
foreach ($f in $pol, $ini) { if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination $bk -Force } }
Write-Output "Backup  : $bk"

# Registry.pol: 'PReg' + version 1, then entries [key;value;type;size;data], strings UTF-16LE with a null.
$entries = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $pol) {
    $b = [IO.File]::ReadAllBytes($pol)
    if ($b.Length -lt 8 -or [Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'PReg') { throw "$pol is not a valid Registry.pol file. Nothing changed." }
    $script:i = 8
    function Read-PolString {
        $start = $script:i
        while (-not ($b[$script:i] -eq 0 -and $b[$script:i + 1] -eq 0)) { $script:i += 2 }
        $s = [Text.Encoding]::Unicode.GetString($b, $start, $script:i - $start)
        $script:i += 2
        $s
    }
    while ($script:i -lt $b.Length) {
        $script:i += 2                                               # [
        $k = Read-PolString; $script:i += 2                          # ;
        $v = Read-PolString; $script:i += 2
        $t = [BitConverter]::ToUInt32($b, $script:i); $script:i += 6
        $n = [BitConverter]::ToUInt32($b, $script:i); $script:i += 6
        $d = New-Object byte[] $n
        [Array]::Copy($b, $script:i, $d, 0, $n); $script:i += $n
        $script:i += 2                                               # ]
        $entries.Add([pscustomobject]@{ Key = $k; Value = $v; Type = $t; Data = $d })
    }
}
$before = $entries.Count
$keep = @($entries | Where-Object { -not ($_.Key -ieq $polKey -and $_.Value -ieq $name) })
$all = @($keep) + [pscustomobject]@{ Key = $polKey; Value = $name; Type = 4; Data = [BitConverter]::GetBytes([uint32]0) }

$ms = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter($ms)
$U = [Text.Encoding]::Unicode
$w.Write([Text.Encoding]::ASCII.GetBytes('PReg')); $w.Write([uint32]1)
foreach ($e in $all) {
    $w.Write($U.GetBytes('[')); $w.Write($U.GetBytes($e.Key + [char]0)); $w.Write($U.GetBytes(';'))
    $w.Write($U.GetBytes($e.Value + [char]0)); $w.Write($U.GetBytes(';'))
    $w.Write([uint32]$e.Type); $w.Write($U.GetBytes(';'))
    $w.Write([uint32]$e.Data.Length); $w.Write($U.GetBytes(';'))
    $w.Write($e.Data); $w.Write($U.GetBytes(']'))
}
$w.Flush()
New-Item -ItemType Directory -Path (Split-Path $pol -Parent) -Force | Out-Null
[IO.File]::WriteAllBytes($pol, $ms.ToArray())
Write-Output "Policy  : Registry.pol written, $($all.Count) entries (other settings kept: $($keep.Count) of $before; Widgets entry set to 0)."

# gpt.ini: bump Version (low 16 bits = computer side) and make sure the registry extension is listed.
$regCse = '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'
$pair = "[$regCse{D02B1F72-3407-48AE-BA88-E8213C6761F1}]"
$lines = @(if (Test-Path -LiteralPath $ini) { Get-Content -LiteralPath $ini } else { '[General]' })
if (-not ($lines -match '^\s*\[General\]')) { $lines = @('[General]') + $lines }
$verLine = $lines | Where-Object { $_ -match '^\s*Version\s*=\s*(\d+)' } | Select-Object -First 1
$ver = if ($verLine) { [int]([regex]::Match($verLine, '\d+').Value) } else { 0 }
$newVer = $ver + 1
if ($verLine) { $lines = $lines -replace '^\s*Version\s*=\s*\d+', "Version=$newVer" } else { $lines += "Version=$newVer" }
$extLine = $lines | Where-Object { $_ -match '^\s*gPCMachineExtensionNames\s*=' } | Select-Object -First 1
if (-not $extLine) {
    $lines += "gPCMachineExtensionNames=$pair"
} elseif ($extLine -notmatch [regex]::Escape($regCse)) {
    # Brackets are kept sorted by extension GUID, as Windows writes them.
    $list = @([regex]::Matches(($extLine -split '=', 2)[1], '\[[^\]]+\]') | ForEach-Object { $_.Value }) + $pair | Sort-Object
    $lines = $lines -replace '^\s*gPCMachineExtensionNames\s*=.*$', ('gPCMachineExtensionNames=' + ($list -join ''))
}
[IO.File]::WriteAllLines($ini, [string[]]$lines, [Text.Encoding]::ASCII)
Write-Output "gpt.ini : Version $ver -> $newVer"

Write-Output 'gpupdate: applying computer policy...'
$ErrorActionPreference = 'Continue'
& gpupdate.exe /target:computer /force 2>&1 | Where-Object { "$_".Trim() } | ForEach-Object { Write-Output "  $_" }

$v = Get-WidgetsValue
if ($v -eq 0) {
    Write-Output "Done: $name = 0 (set by Group Policy). Widgets disappear at the next sign-in."
    exit 0
}
Write-Output "FAILED: $name is still '$v' after gpupdate. Widgets stay on. Backups in $bk."
exit 2
