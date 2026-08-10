# SKYSHIELD MVP Baseline — Capability Statement

**Build:** `garmin-app/SKYSHIELD-MVP-BASELINE.prg`
**Watch:** Garmin Enduro 2 / fenix7x, CIQ 6.0.0, firmware 26.09
**Bridge:** ESP32-S3, `protocol_version 4` (CBOR)

This is an honest statement of what the baseline does and does not do. It exists
so nobody demonstrates a capability that has not been verified, and so the known
limitation is a documented decision rather than a surprise.

## What it DOES — hardware verified

| Capability | Status |
|---|---|
| App starts reliably on the watch | ✅ verified |
| Connects, discovers, subscribes | ✅ verified |
| MTU negotiates to 185 | ✅ verified |
| Real TTSKW07 line → parser → CBOR v4 → BLE → watch alert | ✅ **full chain verified** |
| Sustained alert flow | ✅ ~10 consecutive alerts, no crash |
| Threat haptic on alert | ✅ verified |
| Stable in steady state (MONITOR / LIVE) | ✅ verified |
| LINK LOST shown on a clean disconnect | ✅ verified |
| LINK LOST haptic on a clean disconnect | ✅ present — fires on a real disconnect callback |
| AUTEL as a first-class threat | ✅ T:11/T:12 → `AUTEL`, never `DJI` |
| Confidence reported as null, never 0 | ✅ enforced by contract test |

## What it does NOT do — known limitations

### 1. Abrupt peer disappearance crashes the app — KNOWN LIMITATION

If the ESP32 vanishes **instantly mid-connection** — USB cable pulled, power cut
— the watch app crashes with a Connect IQ System Error instead of degrading to
LINK LOST.

**Why it is accepted for now:**

- The ESP32 is **not on USB in deployment**. It runs from its own power, so an
  instant mid-connection death is a bench artifact rather than a field scenario.
- On this hardware an abrupt loss produces **no disconnect callback at all**
  (observed `c1 d0`). The watch is never told the peer is gone.
- The idle path was verified to touch **zero BLE objects**, so at the moment of
  the pull there is no code of ours running that could fault. The evidence
  points at the Connect IQ BLE stack itself, which Monkey C cannot guard.
- Six attempts to handle it — silent-loss detection, two-phase scan restart,
  settle timers, deferred queues — each either failed or **destabilised normal
  operation**, which is a far worse trade for a demo and for field use.

**Recovery:** relaunch the app. It starts cleanly and reconnects.

### 2. Reconnect after any loss is not verified

Recovery from LINK LOST back to a live link has not been demonstrated end to
end. The reconnect code is present and unchanged from the stable build, but
treat "loses link then recovers on its own" as **unproven**.

### 3. Deliberately removed

- **State-recovery read** — read the last alert on reconnect. Crashed the app
  three times for a cosmetic benefit. Removed; alerts arrive by notification and
  never needed it.
- **Silent-loss detection, two-phase scan restart, heartbeat** — all reverted for
  destabilising steady state.
- **LINK RESTORED haptic** — code present but only reachable after a LINK LOST
  that the app survives, so treat as unverified.

### 4. Diagnostics are off

`DIAGNOSTICS_ENABLED = false` in `BleResourceLog.mc`. No storage access, no
`PREV SESSION CRASHED` screen. `println` output still works. Set `true` to
re-enable the ledger for debugging.

## Safe demo script

1. Power the ESP32 first, let it advertise.
2. Launch the watch app; wait for MONITOR.
3. Inject alerts (serial console, or a live TTSKW07).
4. Show alerts rendering with threat haptics.
5. To show LINK LOST: **power the ESP32 down cleanly** or walk out of range.
   **Do not pull the USB cable while connected.**

## What is verified by automated test

The contract test does not run on the watch, but it does lock the data path:

- **450 checks, 0 failures** across three suites (338 main contract + 64 + 48),
  running the real parser → encoder → decoder against captured TTSKW07 output,
  including exact expected CBOR bytes
- 2 independent CBOR cross-check suites (Python, RFC 8949) — an encoder bug would
  have to be made twice, in two languages, to slip through
- **9/9 guardrail mutations caught**, proving the negative assertions have teeth
  rather than passing vacuously

## Before the China trip / detector integration

1. Confirm this baseline is stable over a long session — an hour-plus with
   alerts flowing, no crash.
2. Confirm the TTSKW07 T-code table against the vendor. Still marked **PENDING
   VENDOR CONFIRMATION** in `docs/ttskw07-format.md`, along with the R-scale
   direction and units.
3. Set the real UART pins and `ACTIVE_DETECTOR = DETECTOR_TTSKW07`. Both are
   still placeholders (RX=18, TX=17).
4. Leave the abrupt-loss limitation alone unless a field failure justifies it.
   The evidence says the fault is below our code, and every attempt to work
   around it has cost steady-state stability.
