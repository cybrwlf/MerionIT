# Hibernation is disabled on every machine, including laptops

Design note. Not implemented yet.

## The problem

`tweaks/basic10-11stuff.ps1` line 90 disables hibernation unconditionally:

```powershell
Write-Host "Disabling Hibernation..."
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" `
    -Name "HibernateEnabled" -Type Dword -Value 0
```

No chassis check. Desktops and laptops get the same treatment.

On a desktop this is reasonable — it reclaims `hiberfil.sys`, which is a meaningful fraction of RAM
on disk, and a desktop is rarely asked to hibernate.

On a laptop it costs three things, and the first one loses user data.

## What it costs on a laptop

Observed on MRM8035-LT101 (Dell Latitude 5520, 2026-09-23), `powercfg /a`:

```
Hibernate       Hibernation has not been enabled.
Hybrid Sleep    Hibernation is not available.
Fast Startup    Hibernation is not available.
```

**1. Battery-critical means shutdown, not hibernate.** The critical battery action can only be set
to hibernate if hibernation is available. Without it, a laptop that runs the battery down powers off
and anything unsaved is gone. This is the one that generates support calls.

**2. No Fast Startup.** Cold boots are slower, every time, for the life of the machine.

**3. No Hybrid Sleep.** Not directly relevant here — this hardware has no S3 anyway (see below).

### Modern Standby makes this worse, not better

Same machine, `powercfg /a`:

```
Standby (S0 Low Power Idle) Network Connected     <- available
Standby (S1/S2/S3)                                <- not supported by firmware
```

The hardware only offers S0 Low Power Idle. Modern Standby keeps the network connected and drains
the battery in "sleep" far more than old S3 did. So the battery-critical path is *more* likely to be
reached on this class of machine, not less — which is exactly the path that needs hibernation to end
safely.

## Options

### A. Leave it. Document the tradeoff.
Zero work. Accepts occasional data loss on laptops and permanently slower boots. Listed so the
decision is explicit rather than inherited.

### B. Enable hibernation everywhere.
Simple, one-line change. Costs disk on desktops for a feature they won't use.

### C. Split by chassis — recommended.
Desktops keep hibernation off; laptops get it on, plus a battery-critical action of hibernate.

The detection already exists — `research/Test-MachineDetection.ps1`, used by `RenamePC.ps1` for the
`DT`/`LT` suffix in machine names. This would reuse the same signal rather than inventing a second
one, so a machine's power config and its name can never disagree.

## Recommendation

**C.** The toolkit already knows whether it's on a laptop; it just isn't using that knowledge here.

## Implementation sketch

1. In `basic10-11stuff.ps1`, gate the hibernation block on chassis type. Desktop path unchanged.
2. Laptop path:
   ```powershell
   powercfg /hibernate on
   powercfg /setdcvalueindex SCHEME_CURRENT SUB_BATTERY BATACTIONCRIT 2   # 2 = hibernate
   powercfg /setactive SCHEME_CURRENT
   ```
3. Verify with `powercfg /a` — `Hibernate` and `Fast Startup` should both move to the available list.

### Gotcha

Flipping `HibernateEnabled` back to 1 in the registry is **not** sufficient. `hiberfil.sys` has to be
recreated, which only `powercfg /hibernate on` does. Any remediation script for already-provisioned
machines has to use `powercfg`, not a registry write.

### Sizing note

`powercfg /hibernate /type reduced` produces a smaller `hiberfil.sys` that supports Fast Startup but
**not** full hibernate. That is the wrong choice here — reason 1 above is the whole point, and it
needs the full type.

## Risk

Low. Worst case is disk consumption on machines that don't need it, which is why this is gated on
chassis rather than applied everywhere. The change is reversible with `powercfg /hibernate off`.

Needs testing on both a laptop and a desktop before it ships, specifically that the chassis
detection agrees with what `RenamePC.ps1` decided for the same machine.
