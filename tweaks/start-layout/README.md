# Windows 11 Start menu layout for new profiles

`win11-start2.bin` is the Start menu pin layout new accounts get on Windows 11.
`tweaks\Set-DefaultUserProfile-*.ps1` copies it into the Default profile at
`C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin`,
so every profile created afterwards starts with it. Windows 10 uses a different Start menu and is skipped.

- Source: Ricardo's own Start menu on MRQ3049-LT601 (Windows 11 Pro 26H2, build 26300), 2026-11-16, after he cleaned it by hand.
- Removed from the Windows default: the XBOX, WhatsApp and Adobe Express placeholders (promoted apps that install on click), plus Microsoft Store and Solitaire & Casual Games (unpinned only, Solitaire stays installed).
- Pins, in order (seen on a brand-new test profile on MRQ3049-LT601, 2026-11-16): Edge, Word, Excel, Outlook (new), Outlook (classic), Settings, Photos, Paint, Calculator, Notepad, Snipping Tool, File Explorer.
- SHA-256: `098B04A7F9B90B3A3CD99AF28893E383C98EEBB21E4851916125816AF8B61DA6` (12,780 bytes).

Things to know:
- A pin for an app that isn't installed on the machine is simply left out.
- Only NEW profiles get it. Existing accounts keep their Start menu.
- To change the layout: set up Start by hand on a Windows 11 machine, copy that user's `start2.bin` from the path above (their own profile), replace this file, and update the hash and source lines here.
- Taskbar pins are separate: they are written by the same script as `LayoutModification.xml`.
