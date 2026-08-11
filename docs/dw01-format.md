# Tatusky DW01 Data Format

**Status: vendor-CONFIRMED on paper. NOT verified against a physical device.**

The format and the complete type-code table below were supplied directly by the
vendor (Kawhi, Tatusky). That is a much stronger footing than the TTSKW07, whose
table was reverse-engineered from screenshots and is still marked *pending*.

What is **not** yet true: no DW01 has been connected. Nothing here has been seen
on real traffic. The parser and its contract test exist so that verification is
a short exercise when the device lands, not a rewrite.

Implementation: [`esp32-bridge/include/DW01Parser.h`](../esp32-bridge/include/DW01Parser.h)
Tests: [`tools/contract-test/dw01_contract_test.cpp`](../tools/contract-test/dw01_contract_test.cpp)

## Transport

| Property | Value |
|---|---|
| Link | BLE push, real time |
| Line settings | 115200 8N1 |
| Encoding | ASCII |
| Sweep range | 0–8000 MHz |

## Record format

Fixed-length placeholders. No separators, no trailing description text — a
different shape from the TTSKW07, which used `F:`/`R:`/`T:` labels, ragged
spacing and a human-readable type string.

```
F5788R093T06C202
 |    |   |   |
 |    |   |   +-- C: purpose UNKNOWN, captured raw, never interpreted
 |    |   +------ T: aircraft type code, TWO HEX DIGITS
 |    +---------- R: signal strength, 0-128, higher = stronger
 +--------------- F: frequency in MHz, four digits
```

| Field | Width | Meaning |
|---|---|---|
| `F` | 4 digits | Frequency in MHz |
| `R` | 3 digits | Signal strength, 0–128, **higher = stronger** (vendor-confirmed) |
| `T` | 2 **hex** digits | Aircraft type code |
| `C` | unspecified | **Unknown.** Captured verbatim, never acted on |

## The hex trap

**`T` is hexadecimal.** `T10` is `0x10` = 16 = AUTEL EVO 2 — *not* decimal 10.

This matters more than it looks. Reading it as decimal does not crash or produce
an obviously broken alert; it produces a **plausible-looking alert with the
wrong threat**, and nothing downstream can tell. Every AUTEL and every FM Analog
contact would be silently misclassified.

A second, quieter trap: **`C` is itself a valid hex digit.** A greedy hex read
of `T06C202` yields `0x06C202`. The parser therefore reads **exactly two** hex
characters and never scans greedily.

Both are pinned by assertions that fail if the parser regresses.

### Consequence: a genuine ambiguity

Fixed-width has one unavoidable cost. `T6C202` is indistinguishable from a valid
code `0x6C` followed by no `C` field. The parser takes the fixed-width reading —
the vendor's stated format — and `0x6C` is unlisted, so it degrades to
`UNKNOWN`. It does **not** guess that the operator meant `T06`. This is pinned
by a test so it stays a known property rather than a surprise.

## Official type-code table — VENDOR CONFIRMED

Codes are hex.

| Code | Type | Models | → threat_type |
|---|---|---|---|
| `0x01` | DJI LB | Phantom 3A/3P/4/4A/4P, Inspire 1/2, Matrice M200 | `DJI` |
| `0x02` | DJI OCU | Mavic, Mavic PRO, P4P V2.0, Mavic 2/2PRO, Air 2, Mini 3, M30 | `DJI` |
| `0x03` | DJI Special | Phantom 4 RTK | `DJI` |
| `0x04` | DJI Special | MINI 2 | `DJI` |
| `0x05` | DJI O3+ | Mavic 3 series, AVATA | `DJI` |
| `0x06` | DJI O3 | DJI FPV, Mavic Air 2S, Mini 3 Pro | `DJI` |
| `0x07` | DJI O4 | O4 video transmission | `DJI` |
| `0x10` | AUTEL SkyLink | EVO 2 | `AUTEL` |
| `0x11` | AUTEL SkyLink | LITE/NANO | `AUTEL` |
| `0x12` | AUTEL SkyLink | EVO 2 PRO | `AUTEL` |
| `0x20` | FM Analog | DIY FPV / fixed-wing aircraft models | `FPV` |
| `0x30` | **WiFi** | Phantom 3S, SPARK, Tello, PARROT series | `UNKNOWN` — see below |
| `0x00` | Unrecognized | — | `UNKNOWN` |
| *anything else* | — | — | `UNKNOWN`, raw code preserved |

The model text is **reconstructed from this table**, because the DW01 wire
format sends no description — unlike the TTSKW07, which appended one. Without
this the model detail would be lost entirely. An unlisted code gets **no** text
rather than an invented one.

> One entry is compressed in code to fit `DRONE_CLASS_CAPACITY` (64 bytes):
> `0x02` ships as `DJI OCU(Mavic/PRO, P4P V2.0, Mavic 2/2PRO, Air 2, Mini 3, M30)`.
> The uncompressed wording is the table row above. The first draft was 64 bytes,
> one over, and `alertSetDroneClass` silently dropped it — the contract test
> caught that, and now asserts the length of every entry.

## Open question: the `C` field

The vendor did not explain `C`. In the one example record it is `C202`.

The parser **captures it verbatim and never interprets it**. It is logged on
every detection so its behaviour against real traffic can be observed — whether
it correlates with channel, count, a checksum, or something else.

**A missing or empty `C` does not break parsing.** Its meaning is unknown, so it
cannot be a precondition for reporting a drone.

To resolve when the device arrives:
1. Does `C` vary with frequency, with type, or independently?
2. Is it always three digits?
3. Does it ever contain non-digits?

## WiFi (`0x30`) — protocol decision pending

The DW01 detects a **WiFi** class the TTSKW07 table had no equivalent for. Our
`threat_type` enum is currently `DJI` / `FPV` / `AUTEL` / `UNKNOWN`.

**Current behaviour:** `0x30` → `UNKNOWN`, with the raw code (`48`) and the full
model text preserved. It is explicitly **not** coerced into `DJI` — Parrot and
Tello are not DJI aircraft, and a false vendor attribution on a threat display
is worse than admitting the class is unmodelled. A test asserts this.

**Recommendation: add `WiFi` as a first-class `threat_type` in protocol
version 5, as a single coordinated bump *after* the DW01 arrives.** Reasoning
and timing are in the handover notes; the short version is that the class is
operationally distinct (short-range, toy-class, often benign), so collapsing it
into `UNKNOWN` discards information an operator would act on differently, and
the AUTEL-in-v4 change is the working precedent.

**Not implemented.** No enum value has been added and no version bumped.

## Normalization policy (SKYSHIELD, not the detector)

The DW01 reports no severity and no confidence. Both are SKYSHIELD decisions:

| Derived | Rule |
|---|---|
| `distance` | `R ≥ 70` → NEAR, `R ≥ 40` → MID, else FAR |
| `severity` | NEAR → HIGH, MID → MEDIUM, FAR → LOW |
| `confidence` | **always absent** (CBOR null), never a fabricated 0 |

**Invariant: a single record can never produce `CRITICAL`.** Escalation is the
watch's job, based on track persistence the bridge does not have. Enforced by
the contract test across the whole R range.

`R` above the stated 128 is **carried and flagged**, not dropped.

## Band mapping

Same thresholds as the TTSKW07:

| Range (MHz) | Band |
|---|---|
| 1100–1350 | 1.2GHz |
| 2350–2550 | 2.4GHz |
| 3200–3600 | 3.3GHz |
| 5650–5950 | 5.8GHz |
| anything else | **UNKNOWN** |

The DW01 sweeps 0–8000 MHz, so out-of-band frequencies are **ordinary traffic,
not errors**. They degrade to `BAND_UNKNOWN` and are never force-fitted to the
nearest band.

## `detector_type_code` is not comparable across detectors

The raw code travels on the wire as before, but note the DW01 value is
**hex-decoded**:

| Record | TTSKW07 sends | DW01 sends |
|---|---|---|
| `T11` / `T:11` | `11` (read as decimal) | `17` (read as hex `0x11`) |
| `T20` / `T:20` | `20` | `32` |

Both still resolve to the same *threat* — the two tables agree — but anything
comparing `detector_type_code` across detectors must account for the base.

### An observation worth putting to the vendor

The two tables are, code for code, **the same table**:

| Code | TTSKW07 (inferred) | DW01 (confirmed) |
|---|---|---|
| `02` | DJI OCU | DJI OCU |
| `05` | DJI O3+ | DJI O3+ |
| `06` | DJI O3 | DJI O3 |
| `11` | AUTEL SkyLink | AUTEL SkyLink |
| `12` | AUTEL SkyLink | AUTEL SkyLink |
| `20` | FM Analog | FM Analog |
| `07` | *"Unknown"* | **DJI O4** |

This strongly suggests the **TTSKW07 codes were hex all along**, and that
`T:07` reading "Unknown" was simply older firmware that predates O4. For codes
`00`–`09` hex and decimal coincide, so the TTSKW07 parser's decimal reading
produces the right answer for every sample we hold — the two interpretations
only diverge in the *stored code value*, not the threat.

**The TTSKW07 parser has deliberately not been changed.** This is an
observation to confirm with the vendor, not a fix to apply on a hunch to a
detector that is being retired.

## Test coverage

`tools/contract-test/dw01_contract_test.cpp` — **706 checks**, run by
`tools/contract-test/run.sh` alongside the TTSKW07 suites.

- the vendor's own example record, field by field
- hex-vs-decimal, asserted per code, including "must NOT equal the decimal misreading"
- all 13 listed codes: threat, raw code, model text, and full CBOR round trip
- AUTEL never becomes DJI or FPV
- WiFi never becomes DJI, FPV or AUTEL
- 8 unlisted codes degrade to `UNKNOWN`, keep the raw code, invent no text
- 9 band cases including 4 deliberately out of band
- severity never `CRITICAL` across the R range
- `C` absent, empty, over-long and non-numeric
- malformed and noise input, plus a null pointer
- every sample record round-trips through the real CBOR codec

## When the device arrives

1. Capture real output and **replace** `esp32-bridge/test_samples/dw01_raw_samples.txt`.
   Today's file is one vendor example plus synthetic records built from the table.
2. Confirm the `C` field's meaning.
3. Confirm `R` really is 0–128 in practice and check the NEAR/MID thresholds
   against observed range.
4. Decide the WiFi enum question.
5. Set the real transport. If the DW01 connects to the ESP32, point
   `DW01Adapter` at the right port and set `ACTIVE_DETECTOR = DETECTOR_DW01`.
   If it connects straight to the watch, port `DW01Parser.h` to Monkey C — the
   logic moves unchanged, which is why it is Arduino-free.
