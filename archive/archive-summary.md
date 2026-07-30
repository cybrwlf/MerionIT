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

Correction (2026-07-28): `tweaks/win10-screensaver.ps1` (still active, called from
`3rd_Step_WIN10.bat`) was initially flagged as having this same broken-path bug - re-checking the
actual file showed that was a mislabeling on the audit's part. It already uses `Ribbons.scr` with
no external image dependency, same as `win11-screensaver.ps1`. No fix needed there.

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

## bginfo-white.bgi — unused light-theme variant

A light-color-scheme BGInfo config, alongside the default `tweaks/bginfo.bgi`. `tweaks/bginfo.ps1`
supports selecting it via `-ConfigFile`, but nothing ever calls it with that override - the
pipeline always uses the default dark variant. Kept in case the light theme is wanted later:
`& tweaks\bginfo.ps1 -ConfigFile archive\bginfo-white.bgi`.

## WIN10-Unpin-Taskbar-Items.ps1 / WIN11-Unpin-Taskbar-Items.ps1 — unwired 2026-07-30, blunt and speculative

Were actively wired into `2nd_Step_WIN11.bat`/`3rd_Step_WIN10.bat` (Step 13 of 14 on Win11) until
Ricardo asked to confirm they'd been turned off. Both scripts nuke the **entire** Taskband
registry key (and, on Win10, delete all pinned-shortcut files outright) - wiping every taskbar
pin, not just unwanted defaults like Task View/Copilot/Microsoft Store. The Win11 version is
openly speculative: it targets a literal placeholder path
(`HKCU:\...\Explorer\TBD`, comment: "though exact key names can vary... an educated guess") and
force-restarts Explorer regardless of whether anything was actually found to clear.

This directly conflicted with the safer approach settled on the same day: Task View and Copilot
are already handled via their own documented, targeted registry toggles in
`tweaks/basic10-11stuff.ps1` (`ShowTaskViewButton`, `ShowCopilotButton`/`TurnOffWindowsCopilot`),
and Microsoft Store's taskbar icon has no reliable automated unpin at all (see
`WIN11-Pin-Taskbar-Items.ps1`'s header - same dead shell-verb subsystem) - it's a manual checklist
item in `Manual-Steps-Reminder.txt` instead. A full taskbar wipe is a much bigger hammer than
either of those and risks clearing pins a tech (or the machine's OEM image) legitimately wants
kept. Kept here for reference only - not verified to still work, not planned to be revived as-is.

## legacy-Merion-repo/ — the original pre-MerionIT-Repo GitHub repo

The whole predecessor project this repo replaced: `cybrwlf/Merion` on GitHub (private, created
2023-12-15, 11 commits, "Merion New Computer Script"). Pulled from GitHub and archived here
2026-07-30, then the GitHub repo itself was deleted per Ricardo's explicit instruction ("archive
it but not use it any more") - this folder is now the only remaining copy of that history.

Contents: `0MerionInstall.ps1`, `0winutil.ps1` (a vendored/forked copy of Chris Titus Tech's
Windows Utility, predating this repo's own winget/Scoop-based `Install-Apps.ps1`),
`1ClearStartMenu.ps1`, `5powerconfig.cmd` (predecessor of this repo's own `powerconfig.cmd`),
`6removebloat-appx.ps1`, `NewComp.ps1`, `singleuser.ps1`, `README.md`, and `Merion.7z` (a 7-zip
archive, contents not inspected - kept as-is for reference).

The numbered-filename convention (`0MerionInstall.ps1`, `1ClearStartMenu.ps1`, `5powerconfig.cmd`,
`6removebloat-appx.ps1`) suggests a simpler, purely sequential run-order predating this repo's
1st/2nd/3rd-Step naming and the RunOnce auto-resume logic. Kept purely as historical record - not
wired into anything, not verified to still work, no plan to revive it (this repo already fully
replaces it).

## installwinget.ps1 — superseded fallback

An older way to bootstrap winget onto a machine that doesn't have it (via a third-party PSGallery
script, `winget-install`). Only ever referenced in a comment inside `Install-Apps.ps1` as a
manual fallback - never actually invoked by anything, and `Install-Apps.ps1` now has its own
tested `Wait-ForWinget` logic that handles this directly. Not verified to still work (the
third-party script it depends on hasn't been checked since this was written).
