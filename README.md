# MerionIT

New-machine / new-user setup scripts for Merion Residential. Public repo — contains **no credentials or account data**.

## Which file do I run?

Double-click as Administrator (they re-launch themselves elevated if you forget). Every one starts
PowerShell with a one-process `-ExecutionPolicy Bypass`, because a fresh Windows install blocks `.ps1`
files by default. The machine's real execution policy is never changed.

| I want to… | Run | Where it gets the scripts |
|---|---|---|
| **Set up a machine** (any situation) | `Setup.bat` | See below. Safe to re-run any time. |
| Just refresh the scripts, start nothing | `Update-Scripts.bat` | GitHub. Needs internet. |
| Add a named user at an already-set-up desk | `Add-User.bat <username>` | Creates the account, then does what setup would have done for them. See "Manual-only" below. |

**`Setup.bat` works out the source for you:**

1. Run from a folder that holds the repo (USB stick, a copy in Downloads) → it **copies that folder** into `C:\MerionIT`. No internet needed. Copy only, nothing on C: is deleted.
2. Run from `C:\MerionIT` itself, or as a lone file, **and GitHub is reachable** → it **pulls the latest** into `C:\MerionIT`.
3. No internet → uses what is already in `C:\MerionIT`.

Then it starts `setup\Step1-Accounts-Apps.ps1`. Anything you add on the command line goes to Step 1:

```
Setup.bat -ForceRename -Unattended -Company MRM -Property 1234 -Year 2026 -NoReboot
```

`Setup.bat /local` skips the GitHub pull in case 2. Use it when you've hand-copied scripts that are newer than what's pushed (a GitHub pull would overwrite them).

If the repo is already on disk and you'd rather type it, from an admin PowerShell:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\MerionIT\setup\Step1-Accounts-Apps.ps1
```

Blank machine, internet only, no files at all (this URL is also what `Jarvis\tools\setup-new-machine.bat` uses, so `bootstrap.ps1` stays in the repo root):

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/cybrwlf/MerionIT/master/bootstrap.ps1 | iex"
```

Re-running is safe. `bootstrap.ps1` tracks exactly which files it placed on disk and only ever touches those, never log files or the real user data `manual\backup-userfiles-20261015-1104.ps1` writes into `backup\`. If Step 1 finds this machine already went through a full setup, it asks for confirmation before reapplying anything (re-running the Win10/11 tweak scripts would otherwise silently reset Start Menu/taskbar customizations someone's made since).

Every stage — `bootstrap.ps1`, Step 1, Step 2, and `Fix-OfficeLanguages.ps1` — writes a full log of its console output to `C:\MerionIT\logs\`, named after whichever one ran (e.g. `Step2-Tweaks-Win11-<timestamp>.log`). If something goes wrong, send that file instead of a screenshot. One exception: `powerconfig.cmd` launches in its own detached window (via `Start`), so its own output isn't captured in the Step 2 log.

## The order things run

1. `Setup.bat` — gets the files into `C:\MerionIT`.
2. `setup\Step1-Accounts-Apps.ps1` — rename (if the name isn't an MRM/MRQ/MRP/MIT one), `pcsadmin` + company accounts, RMM agent check, apps, Office. A rename reboots the machine and Step 1 re-launches itself afterwards (RunOnce).
3. `setup\Step2-Tweaks-Win11.bat` **or** `setup\Step2-Tweaks-Win10.bat` — Step 1 picks the one that matches the OS and launches it. They are alternatives, not a sequence.

`Step1-Accounts-Apps.ps1` runs the account setup, an RMM agent check (skips itself if the agent's already installed), the full app install/update, and Office setup/language cleanup — every machine should have the same apps and a clean English-only Office, so those always fire. Nothing else needs picking from a menu.

`pcsadmin` is created on every run, whatever the computer name. The company account (`TempUser` for MRM, the named user for MRQ) needs the company, which comes from the name prefix. For MRM the 4-digit property code is read from the computer name (`MRM8075-...` → `8075`) and only asked for if the name doesn't carry one.

**Manual-only, never automatic** (all in `manual\`):
- `backup-userfiles-20261015-1104.ps1` — only run this by hand when offboarding someone. Backs up Desktop, Documents, Pictures and the OneDrive folder (including folders OneDrive redirected), verifies the copy, and with `-Remove` deletes the profile, the local account and the stale sign-in screen entry. Run it with `-WhatIf` first (`powershell.exe -ExecutionPolicy Bypass -File C:\MerionIT\manual\backup-userfiles-20261015-1104.ps1 <username> -Remove -WhatIf`). Replaces `backup-userfiles.ps1` and `backup-userfiles-20261013-2319.ps1`, which are still in `manual/` but should not be used.
- `Add-User.bat <username>` — the way to add a user at an already-set-up desk. It runs the newest `Prepare-NewUser-*.ps1`, which (1) creates the account with `SingleUser.ps1` (prompts for the temporary password, so it is fine to leave on disk indefinitely), (2) seeds the Default profile with the per-user settings and taskbar pins that setup only ever gave the setup account (`tweaks\Set-DefaultUserProfile-*.ps1`), (3) checks the machine: BGInfo permissions and its second-pass task are repaired if missing, Kaseya, Huntress, the Windows Update policy and Location are only reported, and (4) arranges for `manual\New-User-Reminder.txt` to open in Notepad once, at the new user's first sign-in. Edit that file to change the checklist. An account that already has a profile is left alone: sign them out and run `tweaks\Set-DefaultUserProfile-*.ps1 -UserName <name>`. `SingleUser.ps1` on its own only creates the account.
- `RemoveUserProfile.ps1` — remove a user profile (`-WhatIf` first).
- Pinning apps to the taskbar of an EXISTING profile — Windows 11 has no working automated way to do this (see `tweaks/WIN11-Pin-Taskbar-Items.ps1`'s header for what was tried and confirmed dead). New profiles are different: they get File Explorer, Edge, Chrome, Word, Excel, Outlook (classic) and Outlook (new) from a taskbar layout that `tweaks\Set-DefaultUserProfile-*.ps1` writes into the Default profile. Snipping Tool is still pinned by hand. `setup\Manual-Steps-Reminder.txt` pops up in Notepad at the end of Step 2 to flag the manual checks after a full setup.

## Automatic cleanup

Once a full setup run finishes, Step 1 deletes the setup-only files that aren't needed once the machine is live (`setup\RenamePC.ps1`, `setup\DefaultAccounts.ps1`, `setup\MITUser.ps1`) — denying anyone who later gets local access a blueprint of how initial setup worked. Everything in `manual\` is deliberately excluded from this. `Setup.bat` or `Update-Scripts.bat` restores the scrubbed files if you need them again.

## Layout

- `Setup.bat`, `Update-Scripts.bat`, `Add-User.bat` — the only things you launch. See the table above.
- `bootstrap.ps1` — the online engine behind `Setup.bat`/`Update-Scripts.bat`. Stays in the root because the `raw.githubusercontent.com/.../bootstrap.ps1` URL is used by one-liners and `Jarvis\tools\setup-new-machine.bat`.
- `setup/` — everything the first-time pipeline runs:
  - `Step1-Accounts-Apps.ps1`, `Step2-Tweaks-Win11.bat`, `Step2-Tweaks-Win10.bat` — the pipeline itself.
  - `RenamePC.ps1` — computer naming (MRM/MRQ/MRP). Desktop-vs-laptop is auto-detected for every company (battery/chassis signals, see `research/Test-MachineDetection.ps1`) with a manual fallback if ambiguous. Purchase year is also auto-detected (CPU generation vs. OS install date) for every company, with a manual fallback for large/undetermined gaps (likely a rebuild); an unattended run (`-Force`) on a CPU the table doesn't know needs an explicit `-Year`. Scrubbed after setup completes.
  - `DefaultAccounts.ps1` — creates `pcsadmin` everywhere, plus `TempUser` (MRM) or the named user (MRQ). Scrubbed after setup completes.
  - `MITUser.ps1` — annual MIT-event loaner account (separate, one-off use). Scrubbed after setup completes.
  - `Install-Apps.ps1` — winget-first/Scoop-fallback app installer/updater, logs to `C:\MerionIT\InstallLog.csv`.
  - `Fix-OfficeLanguages.ps1` — installs Office fresh if missing, strips extra Dell OEM Office language packs if present, no-ops if already correct. Runs automatically every time.
  - `Agent-Install.ps1` — checks for the RMM agent, opens the installer page only if it's missing.
  - `powerconfig.cmd`, `updatePCtime.bat`, `Manual-Steps-Reminder.txt` — power plan, clock sync, and the end-of-setup checklist. Edit the checklist directly to add/remove items; it's plain text.
- `manual/` — run by hand: `Prepare-NewUser-20261016-1210.ps1` (called by `Add-User.bat`), `New-User-Reminder.txt` (the first-sign-in checklist), `SingleUser.ps1`, `backup-userfiles-20261015-1104.ps1`, `RemoveUserProfile.ps1`.
- `tweaks/Set-DefaultUserProfile-20261016-1210.ps1` — writes the per-user settings setup applies to the setup account (Explorer options, taskbar buttons, tips off, about 55 values, each read back) into the Default profile, plus a taskbar pin layout and a one-time first-sign-in checklist, so accounts created later start the same way. Backs up the hive first, only when something will change. `-ReportOnly` changes nothing, `-UserName <name>` applies the values to an existing signed-out profile. Called by `Add-User.bat`; not yet called from Step 2 of full setup. Design: `research\default-user-profile-tweaks.md`.
- `tweaks/` — Win10/11 UI and debloat tweaks (includes `WIN11-Pin-Taskbar-Items.ps1`, kept for reference but NOT wired in — confirmed non-functional on the current Windows 11 build, see its header). `tweaks/vendor-drivers.ps1` branches on `Win32_ComputerSystem.Manufacturer`. Dell gets SupportAssist removed and Dell Command Update installed, silenced and run; every other vendor falls through to Windows Update. Lenovo was evaluated and deliberately uses Windows Update. On Dell it also sets `ExcludeWUDriversInQualityUpdate=1` once DCU is verified working; on every other vendor it *clears* that value, since WU is their only driver path. Prefers `Dell-Command-Update*.EXE` in `C:\MerionIT\apps` (~86 MB, too big for the repo); if that isn't staged it falls back to `winget install Dell.CommandUpdate`. `tweaks/WIN11-removebloat-appx.ps1` must **not** remove Dell Command Update (see that file's header).
- `tweaks/remove-mcafee.ps1` — detects the McAfee OEM trial, strips its five reinstall scheduled tasks, and flags the removal in `setup\Manual-Steps-Reminder.txt`. The removal itself **cannot** be automated: `mccleanup.exe` validates its parent process and refuses to run unless McAfee's own `McClnUI.exe` launched it. Order matters — the hooks have to go before MCPR runs, or McAfee reinstalls itself at the next logon and activates, after which MCPR stops working entirely.
- `tools/` — operational scripts for machines that are **already deployed** (everything in `tweaks/` runs during provisioning; these run afterwards, usually through Kaseya). See `tools/README.md` for ready-to-paste Kaseya commands and how to read the output. `tools/Repair-MerionWindowsUpdate.ps1` brings a deployed machine's Windows Update policy to the current standard (`-ReportOnly` changes nothing). `tools/Diag-WindowsUpdate.ps1` diagnoses a Windows Update loop, then resets the update stack (`-NoReset` collects without clearing).
- `reg/` — registry fixes.
- `docs/` — `OOBE-notes.txt`, the two Yardi URL files (kept for quick reference during manual setup), and `secrets.template.psd1` (the safe blank; the real `secrets.psd1` is never committed and is not synced).
- `research/`, `archive/` — design notes and retired scripts. Repo-only, never synced to a machine.

## Notes

- **OOBE internet bypass**: on the Windows 11 setup screen, press `Shift + F10` to open Command Prompt, then type `oobe\bypassnro` (no spaces) and press Enter to skip the internet-connection requirement. The machine restarts immediately after.
- Large installers (Dell Command Update, MCPR) are not in the repo. Stage them in `C:\MerionIT\apps`; `Setup.bat` copies an `apps\` folder along when you run it from a USB folder that has one.

## Security notes

- Execution policy is only ever set per-invocation (`-ExecutionPolicy Bypass` on the command line) — never persisted system-wide. End users should never be able to run these scripts after setup is complete.
- `setup\RenamePC.ps1`/`setup\DefaultAccounts.ps1`/`setup\MITUser.ps1` are automatically removed from the machine once setup completes (see "Automatic cleanup" above) — they don't need to persist, and leaving them would hand anyone with later local access a blueprint of the account-creation scheme.
- `secrets.psd1` lives only at `C:\MerionIT\secrets.psd1` and is gitignored. Step 1 asks before deleting it (`-DeleteSecrets` to auto-delete; `-Unattended` alone never deletes it).
