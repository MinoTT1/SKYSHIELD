# TTSKW07 Output Format

The Tatusky TTSKW07 handheld drone detector's ASCII line format, and how
SKYSHIELD maps it onto the alert protocol.

- Parser: `esp32-bridge/include/TTSKW07Parser.h`
- Adapter: `esp32-bridge/include/TTSKW07Adapter.h`
- Alert semantics: `protocol/skyshield-alert.schema.json`
- Wire format: `docs/wire-protocol.md`
- Contract test: `tools/contract-test/`

## Provenance

The format below is transcribed from the vendor's **"Handheld Drone Detector
Tool"** live output and export screenshots/videos. The captured lines in
`esp32-bridge/test_samples/ttskw07_raw_samples.txt` are **ground truth** and
must not be edited to make a test pass.

The `T` code table is **derived from those videos and is PENDING VENDOR
CONFIRMATION VIA EMAIL.** Everything marked pending in this document should be
re-checked against the vendor's reply before any field deployment.

This format supersedes the earlier `TTSKW07 TIME=... TYPE=...` shape, which was
invented before real output was available and never existed on the device.

## Transport

Vendor-confirmed: USB Virtual COM, `115200` baud, `8` data bits, no parity, `1`
stop bit, no flow control, ASCII lines.

## Line format

```text
<DATE TIME>   F:<freq>MHz   R:<nnn>   T:<nn>   <type description text>
```

Real captured lines:

```text
06 11:25:36   F:3320MHz   R:093   T:20   FM Analog(DIY FPV, Aircraft model)
06 11:25:48   F:2419MHz   R:043   T:06   DJI O3(FPV, Mavic Air 2s, Mavic Mini 3 Pro)
05-09 09:28:00 F:5773MHz  R:046   T:05   DJI O3+(Mavic 3 series, AVATA)
06 11:27:46   F:2409MHz   R:043   T:02   DJI OCU(Mavic, Mavic Pro, P4P V2.0, Mavic 2, Mavic 2 Pro)
06 14:16:22   F:5768MHz   R:042   T:11   SkyLink(AUTEL Lite/Nano)
06 14:26:30   F:5768MHz   R:046   T:12   SkyLink(AUTEL EVO2 Pro)
06 11:34:56   F:2409MHz   R:023   T:07   Unknown
00-01-01 17:58:38 F:5930MHz R:117  T:07   Unknown
```

### Parsed by label, never by column

Fields are located by their `F:` / `R:` / `T:` labels, searched **in that
order**. Column positions are not used, because:

- the leading timestamp varies in width — `06 11:25:36`, `05-09 09:28:00` and
  `00-01-01 17:58:38` all appear, with one, two or three date components
- the spacing between columns is inconsistent across captures

Searching in order also means a stray `R:` or `T:` inside the trailing
description text cannot be mistaken for a field.

| Field | Extracted as | Notes |
|---|---|---|
| leading text | `timestamp` | captured for the log, **never used for timing** |
| `F:<n>MHz` | `freq_mhz` integer | the `MHz` suffix is ignored |
| `R:<nnn>` | `r_value` integer | leading zeros are normal |
| `T:<nn>` | `t_code` integer | **primary classification input** |
| remainder | `type_text` | preserved verbatim |

## The T code table

**DERIVED FROM VENDOR VIDEOS — PENDING VENDOR CONFIRMATION VIA EMAIL.**

| `T` | Description seen | SKYSHIELD `threat` |
|---:|---|---|
| 02 | `DJI OCU(Mavic, Mavic Pro, P4P V2.0, Mavic 2, Mavic 2 Pro)` | `DJI` |
| 05 | `DJI O3+(Mavic 3 series, AVATA)` | `DJI` |
| 06 | `DJI O3(FPV, Mavic Air 2s, Mavic Mini 3 Pro)` | `DJI` |
| 07 | `Unknown` | `UNKNOWN` |
| 11 | `SkyLink(AUTEL Lite/Nano)` | `UNKNOWN` — see below |
| 12 | `SkyLink(AUTEL EVO2 Pro)` | `UNKNOWN` — see below |
| 20 | `FM Analog(DIY FPV, Aircraft model)` | `FPV` |

The numeric code is the **primary** classification signal, not the text,
because the code is short and stable while the description is long and may be
localized or reworded between firmware revisions.

### An unrecognized T code degrades, it never guesses

A code outside this table:

- **does not fail the line** — the detection is still emitted
- **does not crash**
- maps to `threat: UNKNOWN`
- **is never inferred from the description text**, even when that text
  obviously contains a vendor name
- retains the raw code in the parser diagnostics (logged as
  `T=99 (UNRECOGNIZED CODE, reported as unknown)`)
- retains the full description verbatim in `drone_class`

This is the same philosophy as the enum design: unknown is a real value, and a
guess is worse than an admission. The contract test asserts this against codes
`0, 1, 13, 42, 99, 255`, using a description that says "DJI Something" to prove
the text is not used to manufacture a classification.

## Field mapping

| TTSKW07 | SKYSHIELD | Notes |
|---|---|---|
| `t_code` | `threat` | per the table above |
| `type_text` | `drone_class` | verbatim, carries the model detail |
| `freq_mhz` | `band` | by range; see below |
| `r_value` | `distance` | signal-strength category; see below |
| `r_value` | `severity` | derived policy; see below |
| — | `confidence` | always `null`; the device reports none |
| `timestamp` | *(log only)* | device clock is unreliable |
| `t_code` | *(log only)* | no wire field; see "Open questions" |

`sensor_type` is always `rf`. `source` is always `TTSKW07`.

`alert_kind` is `contact` when the threat **and** the band are both unknown — a
real detection with no usable classification — and `classified` otherwise.

### Band from frequency

| Range (MHz) | Band |
|---|---|
| 1100–1350 | `1.2GHz` |
| 2350–2550 | `2.4GHz` |
| 3200–3600 | `3.3GHz` |
| 5650–5950 | `5.8GHz` |
| anything else | `UNKNOWN` |

Ranges are slightly wider than the nominal ISM allocations so a real detection
at a band edge is not discarded, but they remain bounded: **an out-of-range
frequency degrades to `UNKNOWN` rather than snapping to the nearest band.**
Force-fitting would invent a band the device never reported.

The 5.8 GHz window extends to 5950 rather than the 5900 originally proposed,
because FPV raceband channels run past 5900 — the captured `F:5930MHz` line is
a real example. Without that, a genuine 5.8 GHz detection would have been
reported as an unknown band.

### Signal strength from R — PENDING CONFIRMATION

`R` is treated as a **relative scale, not dBm**. Two assumptions are pending
vendor confirmation:

1. **that higher R means a stronger signal**
2. **that the scale is relative** rather than a physical unit

Observed values range from `023` to `117`, so it is **not bounded at 100**
despite looking like a percentage.

| `R` | `distance` |
|---|---|
| ≥ 70 | `NEAR` |
| ≥ 40 | `MID` |
| < 40 | `FAR` |

These thresholds are a SKYSHIELD normalization policy in
`TTSKW07_DEFAULT_SIGNAL_POLICY`, not a detector claim. `distance` remains a
coarse signal-strength category and is **not physical range**.

### Severity — a middleware policy, not a detector claim

The device reports no severity, but `severity` is a required wire field. It is
derived from the signal category via `TTSKW07_DEFAULT_SEVERITY_POLICY`:

| `distance` | `severity` |
|---|---|
| `NEAR` | `HIGH` |
| `MID` | `MEDIUM` |
| `FAR` | `LOW` |
| unknown | `LOW` |

**It can never yield `CRITICAL`,** and `ttskw07PolicyAvoidsCritical()` asserts
that invariant in the contract test. Nothing in a single detector line justifies
the top severity; escalation is the watch's job, based on track persistence the
bridge does not have. Raising severity because classification *failed* would be
escalation on ignorance, which manufactures false positives.

### Confidence is null, never 0

The device reports no confidence value, so `confidence` is absent (CBOR `null`)
on every TTSKW07 alert and the HUD renders `CONF --`.

It is specifically **not** `0`. On a threat display `CONF 0%` reads as
"certainly not a threat" when the truth is "we have no idea" — the opposite
meaning. This is why `confidence` is nullable in `protocol_version: 3`.

## The device clock is not a time source

`timestamp_ms` on the alert always comes from SKYSHIELD's own monotonic clock,
never from the device line. The captured samples show exactly why:

- `00-01-01 17:58:38` — the device clock was never set
- `05-09 09:28:00` and `06 11:25:36` — inconsistent formats, and dates that do
  not agree with each other

The device timestamp is captured into the parser diagnostics and logged for
traceability, and that is all. See `docs/latency-measurement.md`.

## Robustness

| Input | Result |
|---|---|
| noise, banners, blank lines | `NOT_A_DETECTION` — skipped silently |
| line with no `F:` label | `NOT_A_DETECTION` — skipped silently |
| `F:` present but `R:` or `T:` missing | `MALFORMED` — logged |
| non-numeric or empty field value | `MALFORMED` — logged |
| unrecognized `T` code | **parsed**, degrades to unknown |
| out-of-range frequency | **parsed**, band `UNKNOWN` |
| missing description | **parsed**, `drone_class` omitted |
| ragged/extra whitespace | **parsed** |
| description over 63 bytes | **parsed**, description truncated and flagged |

Non-detections are skipped *silently* on purpose: on a noisy UART, logging an
error per unmatched line would flood the console and bury real problems. Lines
that clearly *are* detections but cannot be used are logged as `MALFORMED`, so
genuine data loss stays visible.

Line assembly is handled by `RawSerialCapture`, which is non-blocking and
delivers at most one complete line per poll.

## Open questions for the vendor

1. **Confirm the T code table.** Codes 02, 05, 06, 07, 11, 12 and 20 are
   observed; the full enumeration is unknown.
2. **Confirm the R scale.** Is higher stronger? Is it relative or a physical
   unit? What is the true maximum, given `117` was observed?
3. **Confirm the timestamp format** and whether the device clock can be
   synchronized over the serial link.
4. **Confirm whether any confidence or severity value is available** under some
   firmware or command mode. If so, the derived severity policy should be
   replaced with the real value and confidence should stop being null.
5. **Confirm the full band list** the hardware can report.

## Proposed protocol changes — flagged, not implemented

Two gaps in the current schema showed up while implementing this parser.
Neither has been acted on, because both change protocol surface.

### 1. `threat` has no Autel value

`threat` is `FPV | DJI | UNKNOWN`. Autel is a distinct manufacturer, so T:11
and T:12 currently map to `UNKNOWN` with the vendor text preserved in
`drone_class`.

This is honest but lossy: the HUD shows `UNKNOWN RF` for a positively
identified Autel airframe. Reporting it as `DJI` would be worse — a false
vendor attribution on a threat display — so `UNKNOWN` stands until the enum is
extended.

**Proposal:** add `AUTEL` to the `threat` enum as wire value `3`. This is a
backward-compatible addition for encoders, but decoders that reject out-of-range
enums would need the new value first, so it requires a coordinated bump.

### 2. The raw `t_code` does not travel on the wire

The numeric code is the most reliable identifier the device produces, and it is
exactly what a field report about an unrecognized protocol would need. It is
currently logged on the bridge only, so the watch never sees it.

**Proposal:** add an optional `detector_type_code` (uint) at CBOR key `16`,
carrying the raw code untranslated. Cost is 2–3 bytes per alert.
