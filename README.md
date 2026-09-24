# MerionIT

New-machine / new-user setup scripts for Merion Residential. Public repo — contains **no credentials or account data**.

## Usage

Fresh Windows machines default to scripts-disabled (no GPO needed to cause this - it's just
PowerShell's out-of-the-box default when no execution policy has been configured anywhere,
confirmed live 2026-07-29). Double-click `bootstrap.bat` as Administrator - it runs the real
bootstrap command with a one-time `-ExecutionPolicy Bypass` that only applies to that single
invocation, never touching the machine's actual policy setting. Every script it calls afterward
(`1st_Step.ps1`, and everything `1st_Step.ps1` itself calls) inherits that same override
automatically, so nothing else needs its own bypass flag.

If the repo's already on disk (e.g. hand-copied via USB before this repo is reachable on
GitHub), skip `bootstrap.bat` and just double-click `1st_Step.bat` directly instead - same
bypass mechanism, one file instead of a download.

Equivalent manual one-liner, if you'd rather type it into an admin PowerShell prompt yourself:

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

- `bootstrap.ps1` (double-click `bootstrap.bat` instead - see Usage above) — entry point, syncs the repo and starts setup.
- `1st_Step.ps1` (double-click `1st_Step.bat` instead if the repo's already on disk) — rename detection, account setup, agent check, app install, OS-version detection, end-of-run cleanup.
- `RenamePC.ps1` — computer naming (MRM/MRQ/MRP). Desktop-vs-laptop is auto-detected for every company (battery/chassis signals, see `research/Test-MachineDetection.ps1`) with a manual fallback if ambiguous. Purchase year is also auto-detected (CPU generation vs. OS install date) for every company, with a manual fallback for large/undetermined gaps (likely a rebuild). Scrubbed after setup completes.
- `DefaultAccounts.ps1` — creates `pcsadmin`/`TempUser` (and legacy `scanner`, unused for new setups) per company. Scrubbed after setup completes.
- `SingleUser.ps1` — new-employee named local account (manual, persists indefinitely).
- `MITUser.ps1` — annual MIT-event loaner account (separate, one-off use). Scrubbed after setup completes.
- `Install-Apps.ps1` — winget-first/Scoop-fallback app installer/updater, logs to `C:\MerionIT\InstallLog.csv`.
- `Fix-OfficeLanguages.ps1` — installs Office fresh if missing, strips extra Dell OEM Office language packs if present, no-ops if already correct. Runs automatically every time.
- `Agent-Install.ps1` — checks for the RMM agent, opens the installer page only if it's missing.
- `tweaks/vendor-drivers.ps1` — branches on `Win32_ComputerSystem.Manufacturer`. Dell gets SupportAssist removed and Dell Command Update installed, silenced and run; every other vendor falls through to Windows Update, which `tweaks/basic10-11stuff.ps1` has already configured. Lenovo was evaluated and deliberately uses Windows Update — System Update is GUI-bound and Thin Installer needs a package repository you have to build and maintain, which doesn't suit properties being bought and sold. On Dell it also sets `ExcludeWUDriversInQualityUpdate=1` once DCU is verified working, so Windows Update stops offering drivers that DCU already handles; on every other vendor it *clears* that value, since WU is their only driver path. Prefers `Dell-Command-Update*.EXE` in `C:\MerionIT\apps` (~86 MB, too big for the repo); if that isn't staged it falls back to `winget install Dell.CommandUpdate`, which is the path remote machines take since nobody can hand-carry a USB to them. Note that `tweaks/WIN11-removebloat-appx.ps1` must **not** remove Dell Command Update — it used to, which silently broke this script (see that file's header).
- `tweaks/remove-mcafee.ps1` — detects the McAfee OEM trial, strips its five reinstall scheduled tasks, and flags the removal in `Manual-Steps-Reminder.txt`. The removal itself **cannot** be automated: `mccleanup.exe` validates its parent process and refuses to run unless McAfee's own `McClnUI.exe` launched it. Order matters — the hooks have to go before MCPR runs, or McAfee reinstalls itself at the next logon and activates, after which MCPR stops working entirely.
- `backup-userfiles.ps1` — offboarding backup (manual).
- `Manual-Steps-Reminder.txt` — opens in Notepad at the end of `2nd_Step_WIN11.bat`/`3rd_Step_WIN10.bat` to flag the handful of things a human still needs to do (taskbar pins, new-employee named account, RMM portal check). Edit this file directly to add/remove checklist items - it's plain text, synced to `C:\MerionIT` like everything else.
- `tools/Diag-WindowsUpdate.ps1` — diagnoses a Windows Update loop ("installs in seconds, demands a reboot, comes back with the same list"), then resets the update stack. Run it, reboot, run it again, compare the two logs in `C:\MerionIT\logs\wu-diag-*.txt`. Captures diagnostics **before** resetting, because the reset deletes `SoftwareDistribution` and the update history lives inside it. `-NoReset` collects without clearing.
- `tweaks/` — Win10/11 UI and debloat tweaks (includes `WIN11-Pin-Taskbar-Items.ps1`, kept for reference but NOT wired in - confirmed non-functional on the current Windows 11 build, see its header).
- `reg/` — registry fixes.
- `2nd_Step_WIN11.bat` / `3rd_Step_WIN10.bat` — later stages, unchanged from the original process.

## Notes

- **OOBE internet bypass**: on the Windows 11 setup screen, press `Shift + F10` to open Command Prompt, then type `oobe\bypassnro` (no spaces) and press Enter to skip the internet-connection requirement. The machine restarts immediately after.
- `Yardi Screening.txt` / `yardi checkscan url.txt` — Yardi resident-screening and check-scan login URLs, kept here for quick reference during manual setup.

## Security notes

- Execution policy is only ever set per-invocation (`-ExecutionPolicy Unrestricted` on the command line) — never persisted system-wide. End users should never be able to run these scripts after setup is complete.
- `RenamePC.ps1`/`DefaultAccounts.ps1`/`MITUser.ps1` are automatically removed from the machine once setup completes (see "Automatic cleanup" above) - they don't need to persist, and leaving them would hand anyone with later local access a blueprint of the account-creation scheme.
