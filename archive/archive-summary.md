# Archive Summary

Files here are never synced to a machine (`bootstrap.ps1` excludes the whole `archive/` folder) -
kept only for reference and in case any of these get revived later. None of these are called
from `1st_Step.ps1`, `2nd_Step_WIN11.bat`, or `3rd_Step_WIN10.bat` as of 2026-07-28. If you bring
one back, move it out of `archive/` and wire it into the relevant Step batch file.

## MRM-screensaver.ps1 — a real, working idea that never got wired in

Downloads a per-property logo image (`https://my.merionresidential.com/bginfo/202309<PropID>.png`,
falling back to a generic "ALL PROPERTIES" image if the property-specific one doesn't exist) and
sets it as the Photo Screensaver background. `$PropID` comes from substring-ing the computer name,
so this only makes sense on a machine that's already been through the rename step. **This is the
real, functional version of the "Merion/property-branded background" idea** - unlike the two files
below, this one actually downloads and uses a real image. If that idea comes back, start here.

## win10-MRM-screensaver.ps1 / win11-MRM-screensaver.ps1 — the same idea, half-built

Both set the Photo Screensaver to point at `C:\MerionIT\bg\Image.png` - but neither one, nor
anything else in the repo, ever downloads or creates that file. These look like an earlier,
incomplete attempt at the same property-branded-background idea that `MRM-screensaver.ps1`
actually finished. Kept for reference only; `MRM-screensaver.ps1` is the one worth reviving.

Note: `tweaks/win10-screensaver.ps1` (still active, called from `3rd_Step_WIN10.bat`) has this
exact same broken-path bug and was NOT archived, since removing it would break the live Win10
pipeline. That one needs an actual fix, not archival - flagged separately.

## ClearStartMenu.ps1 — superseded

Generic (non-OS-specific) Start Menu clearing script using the classic XML `LayoutModificationTemplate`
+ `LockedStartLayout` registry trick. Fully superseded by `WIN10-ClearStartMenu.ps1` /
`WIN11-ClearStartMenu.ps1`, which use a different (direct registry-policy) approach and are
actually wired into the pipeline. Never called even before this cleanup.

## LayoutMod.json — orphaned reference file

A Windows 11 Start Menu pinned-items list (JSON format) - Microsoft Store, Xbox App, WhatsApp,
Spotify, Disney+, TikTok, Instagram, Prime Video, and others, more consumer/OEM-default-looking
than Merion-curated. Never referenced by any script. If Start Menu pin control ever gets revisited
(note: the classic `Export-StartLayout`/`Import-StartLayout` cmdlets are confirmed broken on
current Windows 11 builds - see `tweaks/WIN11-Pin-Taskbar-Items.ps1`'s header for the related
taskbar-pin investigation), this file's content could inform what the *desired* pinned list should
be, even though the mechanism to apply it needs rethinking.

## numlockoff.ps1 — duplicate-content bug

Literal copy of `numlockon.ps1`'s content (same registry sets that turn NumLock ON) - despite the
name, it does not turn NumLock off. Never called from anywhere. If a real "turn NumLock off"
script is ever needed, this file needs to be rewritten, not just renamed back.

## removebloat-appx.ps1 (bare, no OS prefix) — legacy, superseded

An older "Windows 10 Original" bloatware-removal script (see its own `Write-Host` output). Fully
superseded by `WIN10-removebloat-appx.ps1` / `WIN11-removebloat-appx.ps1`, which are actively
wired in and maintained. Never called.

## win11-uninstall-suggestedapps.ps1 — depends on a file nothing creates

Reads app names to uninstall from `C:\merionit\SuggestedAppNames.txt` - no script anywhere in this
repo creates or populates that file, so this would do nothing even if it were wired in. Never
called.
