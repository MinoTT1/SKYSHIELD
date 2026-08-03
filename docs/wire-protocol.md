# SKYSHIELD Wire Protocol

**This is the one canonical wire specification.** If any other document in this
repository describes a different BLE payload format, this document wins and the
other document is historical.

- Semantic source of truth: `protocol/skyshield-alert.schema.json`
- Wire encoding: CBOR (RFC 8949), definite-length, canonical integer keys
- Current `protocol_version`: **3**

The JSON schema defines what an alert *means*. This document defines how that
same model is *encoded on the wire*. They must never diverge; the contract test
in `tools/contract-test/` exists to enforce that.

## Retired formats

| Version | Format | Status |
|---|---|---|
| 1 (`S1\|...`) | pipe-delimited ASCII | **retired** — never fully specified |
| 2 (`S2\|...`) | pipe-delimited ASCII | **retired** — see `PAYLOAD_SPEC.md` (historical) |
| 3 | CBOR map, integer keys | **current** |

Receivers MUST reject any payload whose `protocol_version` is not 3. The old
pipe-delimited decoder has been removed; a decoder that silently accepted both
was the root cause of the protocol drift documented in `ANALYSIS_REPORT.md`.

## Why CBOR

- Self-describing, so a field can be added without a flag-day break.
- Compact: integer keys and small-integer enums keep a typical alert near 40
  bytes where the equivalent JSON envelope is ~180.
- Distinguishes `null` from `0` natively, which the product needs in order to
  say "no confidence data" rather than "0% confident".
- Well-specified, so an independent implementation can be written from the RFC.

## Encoding rules

The payload is a single CBOR **map** with **unsigned integer keys**. Only the
following CBOR major types are used, so both the ESP32 encoder and the Monkey C
decoder stay small and auditable:

- major type 0: unsigned integer (keys, enums, counters, timestamps)
- major type 3: text string, UTF-8 (`drone_class` only)
- major type 4: array (`bands` only)
- major type 5: map (the top-level envelope)
- major type 7 / value 22: `null` (absent `confidence`)

Not used, and rejected by the decoder: negative integers, byte strings, tags,
floats, indefinite-length items. Keeping the accepted subset this narrow means a
malformed or hostile packet has very little surface to work with.

### Key assignments

Keys are permanent. A key is never reused for a different meaning; a retired
field's key is retired with it.

| Key | Field | CBOR type | Required | Notes |
|---:|---|---|---|---|
| 1 | `protocol_version` | uint | yes | must be 3 |
| 2 | `timestamp_ms` | uint | yes | CORE monotonic ms since boot |
| 3 | `sequence` | uint | yes | monotonic packet counter |
| 4 | `sensor_type` | uint enum | yes | |
| 5 | `alert_kind` | uint enum | yes | |
| 6 | `threat` | uint enum | yes | |
| 7 | `severity` | uint enum | yes | |
| 8 | `band` | uint enum | yes | |
| 9 | `distance` | uint enum | yes | |
| 10 | `confidence` | uint 0-100 or null | yes | `null` when no data |
| 11 | `drone_class` | tstr | no | omitted when unknown |
| 12 | `detector_latency_ms` | uint | no | detector-to-CORE latency |
| 13 | `bands` | array[4] uint enum | no | omitted when not reported |
| 14 | `direction` | uint enum | no | experimental |
| 15 | `source` | tstr | no | producing adapter label |

### Enum values

```text
sensor_type   0=rf        1=acoustic  2=radar  3=contact
alert_kind    0=classified 1=contact
threat        0=UNKNOWN   1=FPV       2=DJI
severity      0=LOW       1=MEDIUM    2=HIGH   3=CRITICAL
band          0=UNKNOWN   1=1.2GHz    2=2.4GHz 3=3.3GHz  4=5.8GHz  5=MULTI
distance      0=UNKNOWN   1=FAR       2=MID    3=NEAR
bandStrength  0=NONE      1=LOW       2=MED    3=HIGH
direction     0=FRONT     1=LEFT      2=RIGHT  3=REAR
```

`bands` (key 13), when present, is a 4-element array of `bandStrength` values in
fixed order: `[band_1_2, band_2_4, band_3_3, band_5_8]`.

Note that `0` is the "unknown/least" value for every enum where that concept
exists. This is deliberate: a zero-filled or truncated packet decodes to
something explicitly unknown rather than to a confident false positive.

## Timestamps and what can actually be measured

`timestamp_ms` is **milliseconds since CORE boot**, not Unix epoch. The ESP32-S3
bridge has no RTC and no time synchronization, so an epoch timestamp would be
fabricated. Consumers must treat this value as a monotonic device-local counter.

This has a direct consequence for latency measurement:

- **Detector to CORE** is measurable exactly. Both the ingest time and
  `timestamp_ms` are sampled from the same CORE clock, and the difference is
  transmitted as `detector_latency_ms`. No clock synchronization is involved.
- **CORE to watch** is *not* directly measurable as an absolute one-way latency,
  because the watch clock and the CORE clock have an unknown offset. The watch
  therefore records `rx_ms - timestamp_ms` per packet and tracks the minimum
  observed value across the session as its offset baseline. Each packet is then
  reported as *excess latency above that baseline*, which is a real measurement
  of jitter and queueing delay. The absolute one-way figure is deliberately not
  claimed. See `docs/latency-measurement.md`.

## Payload size and BLE MTU

A typical classified alert encodes to roughly 40-48 bytes; a contact alert is
around 24. Both exceed the 20-byte payload of an unnegotiated 23-byte ATT MTU,
so the bridge requests a larger MTU at startup (`NimBLEDevice::setMTU`).

The encoder enforces a hard ceiling of `SKYSHIELD_MAX_PAYLOAD_BYTES` (currently
180) and refuses to emit anything larger rather than silently truncating. If a
future field pushes packets past the negotiated MTU, the correct fix is explicit
chunking with a continuation flag — not a partial write. Silent truncation would
produce a decodable-but-wrong alert, which is the worst possible failure mode for
a safety-adjacent system.

## Worked examples

Classified FPV alert, sequence 1, 12840 ms since boot, 45 ms detector latency:

```json
{
  "protocol_version": 3, "timestamp_ms": 12840, "sequence": 1,
  "sensor_type": "rf", "alert_kind": "classified",
  "threat": "FPV", "severity": "HIGH", "band": "5.8GHz", "distance": "NEAR",
  "confidence": 87, "drone_class": "FPV", "detector_latency_ms": 45,
  "source": "TTSKW07"
}
```

encodes to (spaces and comments added for readability only):

```text
AD                    map(13)
01 03                 1: 3                      protocol_version
02 19 32 28           2: 12840                  timestamp_ms
03 01                 3: 1                      sequence
04 00                 4: 0   rf                 sensor_type
05 00                 5: 0   classified         alert_kind
06 01                 6: 1   FPV                threat
07 02                 7: 2   HIGH               severity
08 04                 8: 4   5.8GHz             band
09 03                 9: 3   NEAR               distance
0A 18 57              10: 87                    confidence
0B 63 46 50 56        11: "FPV"                 drone_class
0C 18 2D              12: 45                    detector_latency_ms
0F 67 54 54 53 4B 57 30 37   15: "TTSKW07"      source
```

Data-less contact alert — something was detected, nothing could be classified:

```json
{
  "protocol_version": 3, "timestamp_ms": 30110, "sequence": 7,
  "sensor_type": "rf", "alert_kind": "contact",
  "threat": "UNKNOWN", "severity": "LOW", "band": "UNKNOWN",
  "distance": "UNKNOWN", "confidence": null, "source": "TTSKW07"
}
```

```text
AB                    map(11)
01 03                 1: 3
02 19 75 9E           2: 30110
03 07                 3: 7
04 00                 4: 0   rf
05 01                 5: 1   contact
06 00                 6: 0   UNKNOWN
07 00                 7: 0   LOW
08 00                 8: 0   UNKNOWN
09 00                 9: 0   UNKNOWN
0A F6                 10: null                   confidence absent, not zero
0F 67 54 54 53 4B 57 30 37   15: "TTSKW07"
```

The watch renders this as a real detection with no classification. It must not
be shown as `CONF 0%`, and it must not be discarded as a parse error.

## Implementations

There is exactly one encoder and one decoder per platform. Adding a second is
what caused the drift this format replaces.

| Role | Implementation |
|---|---|
| Encode (CORE) | `esp32-bridge/include/SkyShieldCodec.h` (`encodeAlert`) |
| Decode (CORE, tests) | `esp32-bridge/include/SkyShieldCodec.h` (`decodeAlert`) |
| Decode (watch) | `garmin-app/source/CborAlertDecoder.mc` |
| Reference decode (tooling) | `tools/contract-test/skyshield_cbor.py` |

The C++ codec is deliberately free of any Arduino dependency so it compiles and
runs natively under the contract test. The Monkey C decoder mirrors it field for
field and is verified against the same golden vectors.

## BLE transport

Unchanged from the previous version, and still as described in
`docs/ble-gatt-design.md` for the GATT layout:

- Advertised name: `SKYSHIELD-BRIDGE`
- Service UUID: `9f4d0001-7c31-4f9b-9a4b-8f4c0f000001`
- Alert characteristic UUID: `9f4d0002-7c31-4f9b-9a4b-8f4c0f000001`
- Properties: `READ` + `NOTIFY`, one complete alert per notification
- Payload: CBOR bytes as specified above (no framing, no length prefix — the
  notification length delimits the packet)

`READ` is retained so a reconnecting watch can retrieve the most recent alert
without waiting for the next notification.
