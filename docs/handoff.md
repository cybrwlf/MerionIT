# Session Handoff: Add-User flow (Default-profile seeding, taskbar pins, first-sign-in checklist)

## Where it started
The session began as "connect to the bench machine over SSH and tell me where we left off with this test machine". It became building and testing the new-user flow on that bench machine: accounts added after setup now start with the same per-user settings setup gave the setup account, get taskbar pins, and open a short checklist for the tech at first sign-in. Constraints that emerged: this repo is public (no employee names, credentials or IPs in commits, comments or docs), every push to master needs the user's explicit OK, and tech checklists must be concise actions only.

## Decisions locked + what shipped
All on `master` of `cybrwlf/MerionIT`, each pushed after approval:
- `290d859` Add-User now seeds the Default profile, pins taskbar apps and shows a first-sign-in checklist. `Add-User.bat` runs the newest `manual/Prepare-NewUser-*.ps1`: creates the account (`SingleUser.ps1`), runs `tweaks/Set-DefaultUserProfile-*.ps1`, runs machine checks (BGInfo permissions and second-pass task repaired if missing; Kaseya, Huntress, Windows Update policy, Location only reported). Why: setup's per-user tweaks only ever reached the setup account (design note: `research/default-user-profile-tweaks.md`).
- `0b06d1f` Snipping Tool added to the pins; checklist cut to five action lines. `Set-DefaultUserProfile` renamed to `-20261016-1450` (new revision, new timestamp, wrapper finds the newest by wildcard).
- `7c20e20` `manual/backup-userfiles-20261016-1643.ps1`: `-Remove` now also deletes scheduled tasks that run as the removed account (OneDrive Startup/Reporting, Chrome helper, custom jobs), logs each task's command, and reads back that none are left. Task Scheduler stores the run-as account by SID even when registered by name.
- `922b05c` `tweaks/bginfo.ps1`: fixes permissions so BGInfo starts for every user. Local admins run with a filtered token at logon, so a file only Administrators can read is unreadable to them.
- `c0d6c22`, `0a679c1` earlier revision of the removal script (sign-in screen cache cleanup) and README/comment updates.
- `19125f2` cherry-pick of the `Fix-OfficeLanguages` UAC guard (skip the Office scrub unless the signed-in user is a local admin). Branch `restructure-root-layout` was verified fully merged (same patch id) and deleted locally and on GitHub; its old tip was `1ae7d2a`.
- Pins applied to new profiles by a taskbar layout in the Default profile: File Explorer, Edge, Chrome, Word, Excel, Outlook (classic), Outlook (new), Snipping Tool. The Windows Store pin is dropped (PinListPlacement Replace). Verified working at a real first sign-in on Windows 11 25H2.
- Windows refuses to write the `TaskbarDa` (Widgets button) value; it is optional because the machine-wide widgets policy already covers it.
- First-sign-in wallpaper wipe and Explorer restart are NOT from this repo: the unattended Windows install left `C:\Windows\Setup\Scripts\UserOnce.ps1` as a RunOnce (`UnattendedSetup`) in the Default hive; it sets a teal wallpaper, clears the wallpaper value and kills Explorer. Mitigated by the scheduled task `MerionIT BGInfo second pass` (90 s after logon).
- Updating an older install in place: `Update-Scripts.bat`, or the bootstrap one-liner with `-NoLaunch` (files only, starts nothing). A Kaseya-ready form that runs as a script block, with a log tail written with `Write-Output`, was given to the user but has not been run through Kaseya.
- Existing accounts on an already-set-up machine: `tweaks/Set-DefaultUserProfile-*.ps1 -UserName <account>` applies the same values to a signed-out profile. Pins and the checklist cannot be applied to an existing profile.

## Key files for next session
- `research/default-user-profile-tweaks.md`: the design note this implements (updated to say Option A is implemented for Add-User only).
- `manual/Prepare-NewUser-20261016-1210.ps1`, `tweaks/Set-DefaultUserProfile-20261016-1450.ps1`, `manual/New-User-Reminder.txt`, `Add-User.bat`: the flow.
- `manual/backup-userfiles-20261016-1643.ps1`: offboarding and removal.
- `tweaks/bginfo.ps1`, `bootstrap.ps1`, `README.md`.
- Memory files touched (Jarvis work memory, repo `Jarvis-Merion`, commit `ec2c16c`): `project_new-user-defaults-flow.md` (new), `ssh-access-method-merion-laptops.md` (credentials are on the USB at `D:\MerionIT-Test\`, not E:), `merion-pcs-tech-doc-style.md` (checklists are actions only), `MEMORY.md`.

## Running state
- Background processes: none. Two background SSH shells started earlier (`bqr1oo20l`, `b0dpyn5ws`) ended on their own; the temporary SYSTEM watcher task `MI-mmay-watch` was stopped and removed.
- Dev servers / ports: none.
- Open worktrees / branches: only `master` at the repo root; all temporary worktrees removed.

## Verification: how to confirm things still work
- `git log --oneline -8 origin/master` shows `19125f2` on top, then `7c20e20`, `0b06d1f`, `290d859`, `922b05c`.
- On any machine with the scripts: `powershell -ExecutionPolicy Bypass -File C:\MerionIT\tweaks\Set-DefaultUserProfile-20261016-1450.ps1 -ReportOnly` ends with a `RESULT|...|problems=0|mode=report` line.
- On a machine with BGInfo: `Get-ScheduledTask -TaskName 'MerionIT BGInfo second pass'` returns a task, and `Bginfo.exe` is readable by `BUILTIN\Users`.
- Offboarding check: after `backup-userfiles-20261016-1643.ps1 <account> -Remove -Force` the output ends with a `Verified:` line naming profile, account, sign-in entry and scheduled task.

## Deferred + open questions
- Deferred: run the flow end to end from `C:\MerionIT` on the bench machine (`Update-Scripts.bat`, then `Add-User.bat <name>`, then sign in). It has never run that way; the bench machine's `C:\MerionIT` predates the feature.
- Deferred: wire `Set-DefaultUserProfile-*.ps1` into Step 2 of full setup. Without it, new builds are not seeded.
- Deferred: remove the `SetWallpaper` line from the unattended-install `UserOnce.ps1`. It is a Windows deployment file outside the repo.
- Deferred: add `-UseBasicParsing` to the download in `bootstrap.ps1` (Kaseya convention; works today because the zip goes straight to a file).
- Deferred: the `-UserName` mode of `Set-DefaultUserProfile` has never been run against a real existing profile; only its report-only checks and guards were tested. The update does not apply the BGInfo repair to existing machines.
- Done 2026-10-23: archived (not deleted) the superseded `backup-userfiles.ps1` and `backup-userfiles-20261013-2319.ps1` to `archive/`. Checked first: the 1013 version is fully covered by 1016 (1016 also removes the scheduled tasks 1013 only reported). The old 17-line script also copied Videos, Favorites and other profile-root folders that 1016 does not.
- Open: what recreated the empty folder `C:\Users\[old-account]` once, a minute after a new profile's first sign-in. No log names it and process creation is not audited. A SYSTEM watcher on the next first sign-in saw nothing; the only change in between was deleting 12 orphaned tasks. If it returns, delete it and rerun a watcher.
- Open: bench machine cleanup before it leaves the bench: OpenSSH still running, `C:\MerionIT-Test` logs, `C:\Windows\Temp\BGinfo-acl-before.txt`, the `pcsadmin` password, and the [new-hire account], whose password was changed by someone other than the assistant.
- Open: the user said they updated a machine and are signed in as `pcsadmin` with existing users; they were given the `-UserName` commands and offered a test on the bench machine first. No answer yet.

## Pick up here
Run the end-to-end acceptance test on the bench machine, or, if the user wants the in-place update for existing accounts tested first, run `Set-DefaultUserProfile-*.ps1 -UserName <account> -ReportOnly` on the bench machine's existing [new-hire account].
