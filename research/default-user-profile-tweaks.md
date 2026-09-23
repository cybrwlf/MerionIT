# Per-user tweaks don't reach accounts created after provisioning

Design note. Not implemented yet.

## The problem

`2nd_Step_WIN11.bat` runs as whoever launched it — in practice `pcsadmin`. Most of its UI tweaks
write to `HKEY_CURRENT_USER`, so they land in `pcsadmin`'s hive and nowhere else.

`SingleUser.ps1` runs *after* that, and the employee's profile isn't created until their first
logon. That profile is built from the Windows default, so it inherits none of the tweaks.

Observed 2026-09-23: the end user's taskbar was plain Windows 11 while `pcsadmin`'s was correct.
The run log had already said so without anyone reading it —
`Pinned items registry path not found for current user`.

Affected steps: 1, 3, 7, 8, 9, 10, 11, 12, plus the `HKCU` portion of step 2
(`basic10-11stuff.ps1`: notification center, toast notifications, classic right-click menu,
Explorer opens to This PC, known file extensions, Task View / People icons, Outlook nav bar).

This is not specific to one machine. It has been true of every machine where a named account was
added after the tweak stage, which is the normal Merion workflow.

## What is happening today

Nothing. The tweaks are silently absent, and the only signal is that the desktop looks wrong. There
is no check anywhere that compares a new profile against the intended state.

The stopgap is to re-run the eight per-user scripts while logged in as the new user. It works, it
takes about a minute, and it depends entirely on someone remembering.

## Options

### A. Write the settings into the Default User hive — recommended

`C:\Users\Default\NTUSER.DAT` is the template every new profile is copied from. Load it, write the
same values the per-user scripts write, unload it. Any profile created afterward inherits them at
creation, with no logon-time cost and nothing left on disk.

```powershell
reg load "HKU\MerionDefault" "C:\Users\Default\NTUSER.DAT"
# ... Set-ItemProperty against Registry::HKEY_USERS\MerionDefault\... ...
[gc]::Collect()          # PowerShell's registry provider holds handles; unload fails without this
reg unload "HKU\MerionDefault"
```

Fits the existing model: provisioning sets the machine up once, and accounts created later are
correct by construction rather than by remembering a follow-up step.

Covers the taskbar problem, which is the visible complaint.

**Limits.** Registry only. Does not cover anything a script does beyond setting values (AppX
removal, Explorer restarts, `powercfg`). Does not fix profiles that already exist — acceptable,
since the only pre-existing profile is `pcsadmin`, which already has the tweaks.

**Gotcha.** The `reg unload` fails if any handle is still open on the hive. The `[gc]::Collect()`
above is required, not defensive. A failed unload leaves `NTUSER.DAT` locked and can corrupt the
default profile, so the unload needs to be verified rather than assumed.

### B. Active Setup — for anything registry edits can't do

`HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\<GUID>` with a `StubPath` value runs a
command exactly once per user, at that user's first logon, forever. It's the supported mechanism for
this exact problem and it covers users created at any point in the future, not just those created
after provisioning.

Costs: the scripts have to stay on disk permanently (conflicts with the post-setup cleanup, though
`SingleUser.ps1` is already an exception to that), and it runs a visible window at first logon
unless deliberately hidden.

Worth it only for the non-registry work. Overkill if A covers the real complaint.

### C. Leave it manual, document it

Add "re-run the per-user tweaks as the new user" to `Manual-Steps-Reminder.txt`. Zero engineering,
and relies on a human every time. Listed for completeness — the failure mode is exactly what
happened on 2026-09-23.

## Recommendation

Do **A** for the registry settings. It solves the visible problem, matches how the rest of the
toolkit works, and costs one script run at provisioning time.

Revisit **B** only if something genuinely per-user and non-registry turns out to matter.

Either way, add **C**'s reminder line as a backstop, since neither A nor B helps a profile that
already exists.

## Implementation sketch

1. New `tweaks/Apply-DefaultUserTweaks.ps1`. Loads the default hive, writes the values, unloads,
   verifies the unload actually happened.
2. Audit the eight per-user scripts and split each one: registry values move to the new script;
   anything else stays where it is. Scripts that are *purely* registry writes could be dropped from
   `2nd_Step` entirely once their values are in the default hive.
3. Wire it into `2nd_Step_WIN11.bat` and `3rd_Step_WIN10.bat` after the tweak steps, so it captures
   the same settings those steps apply.
4. Verify by creating a throwaway local account, logging in, and confirming the taskbar and Explorer
   settings match `pcsadmin`'s. This is the actual success test — not "the script ran without
   errors", which is what would have passed on 2026-09-23.

## Risk

Editing the default profile hive affects every future user on the machine, and a botched unload can
leave it locked or corrupt. It needs testing on a disposable machine before it goes near a
production build — specifically the unload-verification path, which is the part that can do damage.
