# MerionIT

New-machine / new-user setup scripts for Merion Residential. Public repo — contains **no credentials or account data**.

## Usage

On a fresh Windows 10/11 machine, from an admin PowerShell prompt:

```powershell
powershell.exe -ExecutionPolicy Unrestricted -Command "irm https://raw.githubusercontent.com/cybrwlf/MerionIT/master/bootstrap.ps1 | iex"
```

This syncs the repo to `C:\MerionIT` and launches `1st_Step.ps1`.

Safe to re-run later (e.g. to pick up a newer version of the scripts) - `bootstrap.ps1` tracks exactly which files it placed on disk and only ever touches those, never log files or the real user data `backup-userfiles.ps1` writes into `backup\`. If `1st_Step.ps1` finds this machine already went through a full setup, it asks for confirmation before reapplying anything (re-running the Win10/11 tweak scripts would otherwise silently reset Start Menu/taskbar customizations someone's made since).

Every stage - `bootstrap.ps1`, `1st_Step.ps1`, `2nd_Step_WIN11.bat`/`3rd_Step_WIN10.bat`, and `Fix-OfficeLanguages.ps1` - writes a full log of its console output to `C:\MerionIT\logs\`, named after whichever one ran (e.g. `2nd_Step_WIN11-<timestamp>.log`). If something goes wrong, send that file instead of a screenshot. One exception: `powerconfig.cmd` launches in its own detached window (via `Start`), so its own output isn't captured in the 2nd/3rd Step log.

## What runs automatically vs. manually

`1st_Step.ps1` runs the account setup, an RMM agent check (skips itself if the agent's already installed), the full app install/update, and Office setup/language cleanup - every machine should have the same apps and a clean English-only Office, so those always fire. Nothing else needs picking from a menu.

**Manual-only, never automatic:**
- `backup-userfiles.ps1` — only run this by hand when offboarding someone (`powershell.exe -ExecutionPolicy Unrestricted -File C:\MerionIT\backup-userfiles.ps1`).
- `SingleUser.ps1 <username>` — add one named account to an already-set-up machine (new hire at an existing desk) without re-running the full pipeline. Prompts for its own password at runtime, so it's fine to leave on disk indefinitely.
- Pinning Word/Excel/Outlook/Chrome/Edge/Snipping Tool to the taskbar — Windows 11 has no working automated way to do this (see `tweaks/WIN11-Pin-Taskbar-Items.ps1`'s header for what was tried and confirmed dead). `Manual-Steps-Reminder.txt` pops up in Notepad at the end of `2nd_Step_WIN11.bat`/`3rd_Step_WIN10.bat` to flag this and a couple of other end-of-setup checks a human still needs to do.

## Automatic cleanup

Once a full setup run finishes, `1st_Step.ps1` deletes the setup-only files that aren't needed once the machine is live - denying anyone who later gets local access a blueprint of how initial setup worked. `SingleUser.ps1` is deliberately excluded from this (see above). This replaces the old manual `9th_Step.bat` "delete everything" step entirely - it's automatic now, and surgical rather than a blanket wipe.

## Layout

- `bootstrap.ps1` — entry point, syncs the repo and starts setup.
- `1st_Step.ps1` — rename detection, account setup, agent check, app install, OS-version detection, end-of-run cleanup.
- `RenamePC.ps1` — computer naming (MRM/MRQ/MRP). Scrubbed after setup completes.
- `DefaultAccounts.ps1` — creates `pcsadmin`/`TempUser` (and legacy `scanner`, unused for new setups) per company. Scrubbed after setup completes.
- `SingleUser.ps1` — new-employee named local account (manual, persists indefinitely).
- `MITUser.ps1` — annual MIT-event loaner account (separate, one-off use). Scrubbed after setup completes.
- `Install-Apps.ps1` — winget-first/Scoop-fallback app installer/updater, logs to `C:\MerionIT\InstallLog.csv`.
- `Fix-OfficeLanguages.ps1` — installs Office fresh if missing, strips extra Dell OEM Office language packs if present, no-ops if already correct. Runs automatically every time.
- `Agent-Install.ps1` — checks for the RMM agent, opens the installer page only if it's missing.
- `backup-userfiles.ps1` — offboarding backup (manual).
- `Manual-Steps-Reminder.txt` — opens in Notepad at the end of `2nd_Step_WIN11.bat`/`3rd_Step_WIN10.bat` to flag the handful of things a human still needs to do (taskbar pins, new-employee named account, RMM portal check). Edit this file directly to add/remove checklist items - it's plain text, synced to `C:\MerionIT` like everything else.
- `tweaks/` — Win10/11 UI and debloat tweaks (includes `WIN11-Pin-Taskbar-Items.ps1`, kept for reference but NOT wired in - confirmed non-functional on the current Windows 11 build, see its header).
- `reg/` — registry fixes.
- `2nd_Step_WIN11.bat` / `3rd_Step_WIN10.bat` — later stages, unchanged from the original process.

## Notes

- **OOBE internet bypass**: on the Windows 11 setup screen, press `Shift + F10` to open Command Prompt, then type `oobe\bypassnro` (no spaces) and press Enter to skip the internet-connection requirement. The machine restarts immediately after.
- `Yardi Screening.txt` / `yardi checkscan url.txt` — Yardi resident-screening and check-scan login URLs, kept here for quick reference during manual setup.

## Security notes

- Execution policy is only ever set per-invocation (`-ExecutionPolicy Unrestricted` on the command line) — never persisted system-wide. End users should never be able to run these scripts after setup is complete.
- `RenamePC.ps1`/`DefaultAccounts.ps1`/`MITUser.ps1` are automatically removed from the machine once setup completes (see "Automatic cleanup" above) - they don't need to persist, and leaving them would hand anyone with later local access a blueprint of the account-creation scheme.
