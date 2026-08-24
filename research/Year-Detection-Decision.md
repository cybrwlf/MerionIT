# RenamePC.ps1 auto-detection: how we got here

**Purpose of this file:** enough context for a fresh session (no prior conversation memory) to
independently re-derive the same rule, verify it the same way, and know what's still unproven.
Written 2026-08-14, after wiring machine-type and purchase-year auto-detection into
`RenamePC.ps1`.

## The problem being solved

`RenamePC.ps1` builds a computer name as `{Company}{Property}-{DT|LT}{yy}0{N}`, e.g.
`MRM1234-DT2401`. Two of those four pieces used to require the tech to type an answer by hand
every time:

- **Machine type** (`DT` or `LT`)
- **Purchase year** (the `yy` piece)

Goal: auto-detect both from the machine itself, offline, no internet required, so the tech only
has to type the property/extension code and the unique ID. Falls back to asking manually whenever
the offline signals aren't trustworthy enough to guess - never guess silently on shaky data.

## Machine type: DT vs LT

**Signals used:**
- `Win32_Battery` presence (primary signal - does the machine report a battery at all).
- `Win32_SystemEnclosure.ChassisTypes` (SMBIOS chassis code), cross-checked against the battery
  signal since OEM firmware can report either one inconsistently on its own.

```
$LaptopChassisCodes  = 8, 9, 10, 14, 30, 31, 32
$DesktopChassisCodes = 3, 4, 5, 6, 7, 13, 15, 16
```

**Decision rule:**
- If battery presence and chassis code agree (or chassis is unrecognized but battery is clear) →
  trust it: `LT` if battery present or chassis says laptop, `DT` otherwise.
- **Ambiguous** (has a battery but chassis code says Desktop, or chassis code doesn't land in
  either list) → don't guess. Warn and fall back to asking the tech `[DT/LT]` directly. Example
  called out in `Test-MachineDetection.ps1`'s own comments: a UPS-backed desktop can report a
  battery.

**Verification:** run across every machine logged in `MachineDetection-Log.csv` (see below) -
100% agreement between the detected type and the machine's actual, already-correct name. No
counter-examples found. This is why machine type got a much higher confidence bar than purchase
year (below) - it was allowed to go in as a straight auto-fill.

**Company scope:** originally wired in for MRM only, because MRQ/MRP/MIT were hardcoded to
`"LT"` under the (unverified) assumption that those companies never buy desktops. Later widened
to auto-detect for **all four companies** instead of assuming - if one of those companies is ever
handed a desktop, it now gets named correctly instead of silently mislabeled `LT`.

## Purchase year: the harder problem

**Why this is hard:** no single offline field reliably means "the year this machine was
purchased."

- **BIOS `ReleaseDate`** looked like an obvious candidate. **Confirmed unreliable by a real test
  run**: `MRQ3049-LT101` (an 11th-gen Latitude 5520, actually ~2021-era hardware) reports BIOS
  `ReleaseDate` of **2026**, because the firmware had been updated since purchase. BIOS release
  date reflects the last firmware flash, not manufacture/purchase date. Ruled out.
- **CPU generation → launch year** (via a lookup table, `IntelGenYears.csv`) is knowable and
  stable, but a CPU generation stays on the market for 1+ years, and Merion doesn't necessarily buy
  a machine the same year its CPU launched. So CPU year is a *floor*, not the actual purchase
  year.
- **OS `InstallDate`** doesn't drift the way BIOS date does (it only changes on an actual
  reinstall), so it became the second signal: compare it against the CPU-generation launch year.

**The lookup table** (CPU generation → launch year, separate laptop/desktop years since mobile
and desktop SKUs of the same generation often launch months apart) lives in two places:
- `research/IntelGenYears.csv` - source of truth, hand-maintained.
- `$GenYearTable` inline inside `RenamePC.ps1` - a manually-copied duplicate, **not** read from
  the CSV at runtime. Reason: `bootstrap.ps1` deploys `RenamePC.ps1` by downloading the actual
  GitHub repo as a zip and syncing it to `C:\MerionIT` - it does not sync `research/`, and even if
  it did, `.gitignore` has a blanket `*.csv` rule, so `IntelGenYears.csv` is never committed to git
  and never present on a real deployed machine. **If `IntelGenYears.csv` is ever updated, the
  inline copy in `RenamePC.ps1` has to be updated by hand to match** - there's no automatic sync
  between the two.

### The rule (decided 2026-08-14)

Let `cpuYear` = CPU generation's launch year (Laptop or Desktop column, matching the detected
machine type). Let `osInstallYear` = `Win32_OperatingSystem.InstallDate.Year`. Let
`gap = osInstallYear - cpuYear`.

| Gap | Action |
|---|---|
| `0` | Use that year directly - both signals agree, no ambiguity. |
| `1` to `3` | Use `osInstallYear`. This is the "normal buying lag" band - the working theory is that Merion typically buys machines with a given CPU generation one to a few years after that generation launches, so the OS install date (reflecting when this specific unit was actually imaged/deployed) lands a bit after the CPU's launch year. |
| Can't be determined (CPU generation didn't match anything in the table, or no OS install date available), or gap `> 3` | Fall back to asking the tech `Read-Host "Year Purchased?..."`, same as before. A gap this large usually means a **rebuild**: older hardware being reused/reimaged for a new deployment, not a genuine same-era purchase. |

### How the rule was verified - and what it found

The verification data source is `research/MachineDetection-Log.csv`, produced by
`research/Test-MachineDetection.ps1` (a read-only, standalone diagnostic script - never part of
the bootstrap-synced pipeline, meant to be run off a USB stick against real, already-correctly-
named machines to check detected signals against known-true answers before automating anything).

As of 2026-08-14, 8 distinct real machines had been logged (excluding one machine that had never
been renamed, and excluding duplicate re-runs of the same machine). For each, `cpuYear` and
`osInstallYear` were computed as above and compared against the *true* purchase year - trusted as
whatever year the machine's own (already-established, correctly-set) name encodes:

| Machine | CPU launch year | True year (from name) | OS install year | CPU→OSInstall gap | Rule's answer |
|---|---|---|---|---|---|
| MRM8065-DT201 | 2020 | 2022 | 2022 | 2 | ✅ correct (2022) |
| MRP3068-LT502 | 2023 | 2025 | 2025 | 2 | ✅ correct (2025) |
| MRP7593-LT501 | 2023 | 2025 | 2025 | 2 | ✅ correct (2025) |
| MRQ7592-LT301 | 2023 | 2023 | 2025 | 2 | ❌ **wrong (2025, should be 2023)** |
| MIP3004-LT301 (sibling co.) | 2023 | 2023 | 2025 | 2 | ❌ **wrong (2025, should be 2023)** |
| MRQ3049-LT101 | 2020 | 2021 | 2026 | 6 | falls back to manual (correct call - gap > 3) |
| MRQ3049-LT001 | 2019 | 2020 | 2026 | 7 | falls back to manual (correct call) |
| MITLOAN-LT801 | 2018 | 2018 | 2025 | 7 | falls back to manual (correct call) |

**Score inside the band the rule actually auto-decides (gap 1-3): 3 correct / 2 wrong (60%).**
The 3 gap-6/7 cases were all correctly punted to manual entry rather than guessed - the `>3`
threshold is doing its job there.

**Why the 2 failures happened:** both `MRQ7592-LT301` and the MIP machine were purchased the
*same year* their CPU launched (true gap = 0), but had Windows reinstalled roughly 2 years later
for unrelated reasons (troubleshooting, refresh, whatever). A same-year purchase with a later
reimage produces the *exact same* "gap of 2" signature as a genuine 2-year buying lag - there is
no signal currently being logged that tells these two situations apart. This matches a limitation
already flagged in `Test-MachineDetection.ps1`'s own header comments: "OS `InstallDate` is only
meaningful the same day as a fresh OOBE setup - useless on a revisited/reimaged machine." These
two machines are, by definition, revisited/reimaged machines.

**Decision (Ricardo, 2026-08-14): wire the rule in anyway.** Reasoning: the same final
"Is `<name>` correct? [Y/N]" prompt already relied on for machine-type detection is the safety
net here too - a wrong auto-filled year still gets shown to the tech before the rename actually
happens. 60% correct-with-a-visible-check beats 0% (fully manual, and just as capable of a typo)
and is strictly better than what existed before. The alternative (falling back to manual for
*any* nonzero gap, or waiting for a bigger sample before deciding at all) was explicitly
considered and rejected in favor of shipping this now.

## What's still open / unproven

- **Not yet run against a real machine in the field.** Everything above was verified against
  logged/historical data (`MachineDetection-Log.csv`), not by actually running the updated
  `RenamePC.ps1` during a live setup. Next real-machine setup should be watched to confirm it
  behaves as expected.
- **Sample size is small** (8 machines, only 5 in the gap-1-3 band). If more field data comes in
  and the 60% figure moves a lot in either direction, the "wire it in anyway" call might deserve a
  second look.
- **No signal currently distinguishes "genuine buying lag" from "same-year purchase + later
  reimage."** If a better signal ever turns up (e.g. some way to detect number of OS
  reinstalls, or an OEM-side purchase-date field), it could close this gap directly instead of
  just accepting the current error rate.
- **`IntelGenYears.csv` vs `$GenYearTable` drift risk.** These are two independent copies of the
  same data. There's no tooling today that checks they still match after an edit to one but not
  the other.

## Where the actual code lives

- `RenamePC.ps1` (repo root) - the auto-detection logic itself, in the block between the
  property/extension prompt and the final name-confirmation prompt. Header comment there
  summarizes the same rule as here, more tersely.
- `research/Test-MachineDetection.ps1` - the read-only audit tool the verification data came
  from. Still standalone; still not part of the bootstrap-synced pipeline.
- `research/MachineDetection-Log.csv` - the raw logged data the table above was built from.
- `research/IntelGenYears.csv` - the CPU-generation-to-year lookup table (source of truth; keep
  `$GenYearTable` in `RenamePC.ps1` in sync with this by hand if it's ever updated).
- `MerionIT-PRD.md` (in `Work-Business\`, one level up from this repo, not committed to git) -
  Known Issue #7 and Open Question #6 track this at a higher level, alongside the rest of the
  MerionIT toolkit's open issues.
