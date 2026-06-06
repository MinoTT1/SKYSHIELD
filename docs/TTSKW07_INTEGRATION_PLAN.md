# Tatusky TTSKW07 Integration Plan

## Purpose

This document defines the planned integration path for the Tatusky TTSKW07 detector. Implementation of its parser must follow real output capture and validation.

## Vendor-Confirmed Parameters

- USB Virtual COM Port
- `115200` baud
- parity: none
- data bits: `8`
- stop bits: `1`
- flow control: none
- ASCII output
- real-time detection event output
- exported alarm logs
- reported fields:
  - detection time
  - drone type
  - frequency band
  - signal strength

## Bring-Up Steps

1. Connect the TTSKW07 and identify its COM port.
2. Open the serial connection at `115200 8N1` with no flow control.
3. Capture idle output before detection activity.
4. Capture output during a controlled detection event.
5. Store the raw captures without modification.
6. Compare idle, detection, and exported alarm-log formats.
7. Update `TTSKW07Parser` only after the real format is captured and understood.

## Mapping Plan

```text
raw TTSKW07 line
    -> SkyShieldEvent
    -> S2 payload
    -> Garmin HUD
```

The parser should preserve source data faithfully before normalization. S2 generation should use only fields confirmed by the detector output.

## Integration Risks

- The exact ASCII line format is still unknown.
- Do not assume CSV or JSON until real output is captured.
- Do not fake severity.
- Do not fake confidence.
- Missing fields must remain unknown rather than inferred without evidence.
