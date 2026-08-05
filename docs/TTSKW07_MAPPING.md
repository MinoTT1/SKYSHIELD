# TTSKW07 to SKYSHIELD Mapping (SUPERSEDED)

> **This document describes a line format that does not exist.**
>
> It was written against `TTSKW07 TIME=... TYPE=... BAND=... SIGNAL=...` sample
> lines that were invented before any real detector output was available. The
> device's actual format is completely different:
>
> ```text
> 06 11:25:36   F:3320MHz   R:093   T:20   FM Analog(DIY FPV, Aircraft model)
> ```
>
> The current mapping is **[docs/ttskw07-format.md](ttskw07-format.md)**, based
> on real captures from the vendor's tool.
>
> Kept only for the reasoning behind the four normalization decisions, which
> carried over unchanged to the real parser: confidence stays null rather than
> 0, a failed classification never escalates to CRITICAL, Autel is never
> reported as DJI, and model text is preserved verbatim.

How a raw Tatusky TTSKW07 detection line becomes a SKYSHIELD alert.

- Parser: `esp32-bridge/include/TTSKW07Parser.h`
- Adapter: `esp32-bridge/include/TTSKW07Adapter.h`
- Alert semantics: `protocol/skyshield-alert.schema.json`
- Wire format: `docs/wire-protocol.md`
- Transport and vendor parameters: `docs/TTSKW07_INTEGRATION_PLAN.md`

## Input

Vendor-confirmed transport: USB Virtual COM, `115200 8N1`, no flow control,
ASCII, real-time detection output.

Observed line format, from the captures in
`esp32-bridge/test_samples/ttskw07_raw_samples.txt`:

```text
TTSKW07 TIME=00:00:01 TYPE=DJI_MAVIC BAND=2.4GHz FREQ_MHZ=2437 RSSI=-61DBM SIGNAL=MID
```

Fields are parsed **by key name, not by position**, and unrecognized keys are
ignored, so a firmware revision that adds or reorders fields will not break
parsing.

`TYPE`, `BAND` and `SIGNAL` are required. A line missing any of them carries
nothing actionable and is rejected as malformed. Lines that do not begin with
the `TTSKW07` token (UART noise, boot banners, blank lines) are skipped
silently rather than logged as errors, because on a noisy link that would flood
the console.

## Field mapping

| TTSKW07 | SKYSHIELD | Notes |
|---|---|---|
| `TYPE=DJI_*` | `threat: DJI` | |
| `TYPE=FPV*` | `threat: FPV` | |
| `TYPE=AUTEL_*` | `threat: UNKNOWN` | see decision 3 |
| `TYPE=<other>` | `threat: UNKNOWN` | |
| `TYPE=<value>` | `drone_class` | detector's own string, preserved verbatim |
| `BAND=2.4GHz` etc. | `band` | direct enum mapping |
| `BAND=MULTI` | `band: MULTI` | |
| `BAND=<unrecognized>` | `band: UNKNOWN` | degrade, never guess |
| `SIGNAL=NEAR/MID/FAR` | `distance` | signal-strength category, not range |
| `SIGNAL` | `severity` | derived; see decision 2 |
| — | `confidence: null` | not reported; see decision 1 |
| `RSSI=-61DBM` | *(log only)* | no schema field |
| `FREQ_MHZ=2437` | *(log only)* | no schema field |
| `TIME=00:00:01` | *(log only)* | detector-local, not a usable clock |

`sensor_type` is always `rf`. `source` is always `TTSKW07`.

`alert_kind` is `contact` when `TYPE` and `BAND` are both unknown — a real
detection with no usable classification — and `classified` otherwise.

## Decisions, and why they depart from the old fixture

`docs/TTSKW07_INTEGRATION_PLAN.md` states plainly:

> Do not fake severity. Do not fake confidence. Missing fields must remain
> unknown rather than inferred without evidence.

The retired fixture `expected_s2_payloads.txt` violated that in four places.
The parser follows the integration plan; the fixture has been replaced. Each
departure is listed here so it can be reviewed and overruled deliberately.

### 1. Confidence is null, never a number

The TTSKW07 does not report confidence. The old `S2` format had no confidence
field at all, so the question never arose; it does now.

Confidence is therefore **absent** (CBOR `null`) on every TTSKW07 alert, and
the HUD renders `CONF --`.

It is specifically *not* set to `0`. On a threat display, `CONF 0%` reads as
"certainly not a threat" when the truth is "we have no idea" — the opposite
meaning. This is the reason `confidence` was made nullable in
`protocol_version: 3`.

### 2. Severity is a documented middleware policy, not a detector claim

The TTSKW07 does not report severity, but `severity` is a required wire field.
It is derived deterministically from the detector's own `SIGNAL` value:

| `SIGNAL` | `severity` |
|---|---|
| `NEAR` | `HIGH` |
| `MID` | `MEDIUM` |
| `FAR` | `LOW` |
| unknown/absent | `LOW` |

This is a **SKYSHIELD normalization policy**, not something the detector
asserted, and it must be described that way in any operator-facing material.

**It never yields `CRITICAL`.** Nothing in TTSKW07 output justifies the top
severity level. Escalation to `CRITICAL` remains the watch's job, based on
track persistence (`LOCKED`) and repetition — evidence the bridge does not
have from a single line.

The old fixture escalated an *unclassifiable* detection to `CRITICAL`
(`S2|U|C|X|N|UNKNOWN`). Raising severity because classification failed is
escalation on ignorance, and it manufactures exactly the false positives this
product cannot afford. A `TYPE=UNKNOWN` line is now `HIGH` when `SIGNAL=NEAR`,
on the strength of the signal alone.

### 3. Autel is not DJI

The old fixture mapped `TYPE=AUTEL_EVO` to threat `D` (DJI). The `threat` enum
has only `FPV`, `DJI` and `UNKNOWN`, and Autel is a different manufacturer.

Autel now maps to `threat: UNKNOWN` with `drone_class: AUTEL_EVO`. No
information is lost — the real vendor string travels in `drone_class` — and no
false vendor attribution is made. A HUD claiming "DJI" for an Autel airframe
would be actively misleading in the field.

### 4. Model names are preserved, not remapped

The old fixture reported `TYPE=DJI_O3` as drone class `MAVIC`. An O3 air unit
is not a Mavic.

`drone_class` now carries the detector's own `TYPE` string verbatim
(`DJI_O3`, `DJI_MAVIC`, `FPV_ANALOG`, `AUTEL_EVO`). This follows the
integration plan's instruction to preserve source data faithfully before
normalization.

If the string does not fit `drone_class` (24 bytes), the label is dropped but
**the detection is kept**: threat family, band and signal are still valid, and
discarding a real detection over a cosmetic field would be the worse failure.

## Worked results

Parsing the five captured detection lines produces:

| Raw `TYPE` / `BAND` / `SIGNAL` | kind | threat | band | distance | severity | confidence | drone_class |
|---|---|---|---|---|---|---|---|
| `DJI_MAVIC` / `2.4GHz` / `MID` | classified | DJI | 2.4GHz | MID | MEDIUM | null | `DJI_MAVIC` |
| `DJI_O3` / `5.8GHz` / `NEAR` | classified | DJI | 5.8GHz | NEAR | HIGH | null | `DJI_O3` |
| `FPV_ANALOG` / `5.8GHz` / `NEAR` | classified | FPV | 5.8GHz | NEAR | HIGH | null | `FPV_ANALOG` |
| `AUTEL_EVO` / `2.4GHz` / `MID` | classified | UNKNOWN | 2.4GHz | MID | MEDIUM | null | `AUTEL_EVO` |
| `UNKNOWN` / `MULTI` / `NEAR` | classified | UNKNOWN | MULTI | NEAR | HIGH | null | `UNKNOWN` |

The sixth captured line, `NOISE UART FRAME DROPPED 0x00 0xFF`, and the trailing
whitespace line are both correctly skipped as non-detections.

These rows are asserted by the contract test; see `tools/contract-test/`.

## Open item for vendor confirmation

The captured samples are the only evidence of the line format available. They
are consistent and realistic, but if the vendor supplies a specification that
contradicts them — different key names, a different `SIGNAL` vocabulary, or
additional severity/confidence fields the detector actually reports — this
mapping must be revisited before any field use. In particular, if the TTSKW07
does report a confidence value under some firmware, decision 1 should be
reversed and the real value carried on the wire.
