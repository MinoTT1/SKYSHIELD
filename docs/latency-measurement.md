# Latency Measurement

How SKYSHIELD measures the time an alert takes to travel from a detector to an
operator's wrist, and — just as importantly — which parts of that journey it
does **not** claim to measure.

The governing rule: **every number reported is a measured difference between
two readings of the same clock.** Nothing is estimated, defaulted, or inferred.
Where a segment cannot be measured honestly, the output says so rather than
printing a plausible figure.

## The segments

```text
    detector line          normalization        handed to           drawn on
      in hand                finished          BLE notify()         the HUD
         |                      |                   |                   |
         |======== A ==========>|======== B =======>|                   |
         |                                          |===== C =====>|    |
         |                                          (unmeasured)   |=D=>|
         |                                                              |
    [--------------- ESP32 clock ---------------]  [--- watch clock ---]
```

| Segment | Span | Clock | Status |
|---|---|---|---|
| **A** | detector line ingested → normalization finished | ESP32 only | **Measured** (real detector only) |
| **B** | normalization finished → handed to `notify()` | ESP32 only | **Measured** |
| **C** | `notify()` → notification received on watch | **spans both** | **Not measured** — see below |
| **D** | notification received → alert drawn on HUD | watch only | **Measured** |

A, B and D are each bounded by two reads of a single monotonic clock, so each
is a valid duration. C is the one segment that crosses the device boundary, and
that is exactly why it is not reported as a number.

## Why C cannot simply be subtracted

`timestamp_ms` is milliseconds since **ESP32 boot**. The watch's
`System.getTimer()` is milliseconds since **app start**. These are two
independent monotonic counters with an unknown, arbitrary offset — the ESP32
may have been powered for hours before the watch app opened.

So:

```text
watch_rx_ms - core_tx_ms  =  true_transport_time + unknown_clock_offset
```

The offset term can be minutes or hours, and it dominates completely. Printing
that subtraction as a latency would produce a number that looks precise and is
meaningless. The bridge therefore logs:

```text
LATENCY seq=7 C_tx_to_watch=unmeasured (cross-clock) core_tx_ms=41230
```

### What *is* measured across the link

Although absolute C is unavailable, its **variation** is measurable, and that
is genuinely useful. `LatencyMonitor` on the watch tracks the minimum raw
difference seen during the session:

```text
baseline = min(watch_rx_ms - core_tx_ms)   over all packets
excess   = (watch_rx_ms - core_tx_ms) - baseline
```

The baseline corresponds to the fastest packet observed, so it absorbs the
constant clock offset. Everything above it — `transport_excess` in the log — is
real queueing delay and jitter, measured in true milliseconds.

**`transport_excess` is jitter, not one-way latency.** A reading of `+0ms` means
"as fast as the best packet this session", not "instantaneous".

## Getting an absolute figure for C — not implemented

Obtaining a real absolute C requires a round trip, so the measurement stays on
one clock:

1. ESP32 records `t0 = millis()` and sends an alert carrying its sequence.
2. The watch, on receipt, writes that sequence back to an **ack characteristic**.
3. ESP32 records `t1 = millis()` on the write and computes `rtt = t1 - t0`.

Both `t0` and `t1` are ESP32 reads, so `rtt` is valid. One-way latency is then
estimated as `rtt / 2`.

**This is deliberately not implemented.** It is flagged for a decision because:

- It requires a **new writable GATT characteristic**, which is a protocol
  surface change beyond the scope this work was given.
- `rtt / 2` assumes a symmetric path, and BLE is not symmetric. Transmission is
  quantized to the **connection interval** (typically 7.5–50 ms), so the halved
  figure is bounded by that granularity, not by the real air time. Below roughly
  one connection interval the estimate carries no information.
- It adds watch→bridge traffic on every alert, which costs power on both
  devices for a number that is diagnostic rather than operational.

A more accurate alternative, if C ever needs to be known precisely, is to
measure the connection interval directly and treat it as the dominant term,
rather than inferring latency from an RTT that is mostly connection-interval
quantization.

**Recommendation:** leave C unmeasured. A + B + D bracket everything SKYSHIELD
controls, and `transport_excess` already detects a degrading link. Absolute C is
dominated by the BLE connection interval, which is a negotiated parameter that
can be read directly if it matters.

## Segment A is only real with a real detector

Segment A is measured by the detector adapter and carried in
`detector_latency_ms`.

`SerialInjectAdapter` — the bench harness where an operator types an alert into
the console — **deliberately leaves this field absent**. Its "ingest" moment is
when a human finished typing, so the delta would measure the parser and nothing
else. Reporting that as detector latency would put a real number in a field
describing something it did not measure, and it would read as a suspiciously
excellent `0ms`.

The bridge prints:

```text
LATENCY seq=3 A_detector_to_core=n/a (source 'SERIAL_INJECT' has no detector ingest) B_core_to_tx=1ms [single ESP32 clock, measured]
```

**Segment A becomes real only with a physically connected TTSKW07** on the UART,
with `ACTIVE_DETECTOR = DETECTOR_TTSKW07`.

## Running a measurement

### Bridge side

1. Flash the firmware. `LOG_LATENCY` defaults to `true` in `main.cpp`.
2. Open the serial monitor at 115200.
3. Connect the watch and let it subscribe.
4. Trigger an alert — paste a TTSKW07 line in inject mode, or let a connected
   detector produce one.

Expected output per alert:

```text
notify sent: 48 bytes
LATENCY seq=4 A_detector_to_core=n/a (source 'SERIAL_INJECT' has no detector ingest) B_core_to_tx=1ms [single ESP32 clock, measured]
LATENCY seq=4 C_tx_to_watch=unmeasured (cross-clock) core_tx_ms=41230
```

With a real detector attached, the first line instead reads:

```text
LATENCY seq=4 A_detector_to_core=3ms B_core_to_tx=1ms A+B_in_bridge=4ms [single ESP32 clock, measured]
```

### Watch side

Watch logs appear in the Connect IQ simulator console, or via
`monkeydo` on hardware.

```text
LATENCY seq=4 core_tx=41230 rx=118442 raw_delta=77212 baseline=77208 transport_excess=4ms detector_to_core=n/a samples=6 dropped=0
LATENCY seq=4 D_rx_to_shown=118ms worst=241ms [single watch clock, measured]
```

## Reading the output

| Field | Meaning | Trust |
|---|---|---|
| `A_detector_to_core` | detector line → normalized | Valid, or `n/a` |
| `B_core_to_tx` | normalized → `notify()` | Valid |
| `A+B_in_bridge` | total time inside the bridge | Valid |
| `C_tx_to_watch` | always `unmeasured` | — |
| `D_rx_to_shown` | received → drawn | Valid |
| `raw_delta` | `rx - core_tx` | **Meaningless alone** — includes clock offset |
| `baseline` | session minimum `raw_delta` | Reference only |
| `transport_excess` | `raw_delta - baseline` | Valid **jitter**, not one-way latency |
| `dropped` | gaps in the bridge sequence | Valid packet-loss count |

`D_rx_to_shown` includes the wait for the next render tick, so it is quantized
by the UI timer (250 ms) and will typically land well above the decode cost. It
measures time-to-operator-visible, which is the number that matters, not decode
speed.

`dropped` comes from gaps in the monotonic `sequence` field and is a transport
quality signal independent of latency.

## What is deliberately absent

- No absolute one-way transport latency. See above.
- No end-to-end "detector to wrist" total. It would have to span both clocks and
  would inherit the same offset problem. A + B and D are reported separately;
  they must not be added to a cross-clock figure and presented as a total.
- No latency shown on the HUD. `LatencyMonitor.formatSummary()` exists for
  debugging and returns `LAT --` before the first sample rather than `0`.

## Related

- `docs/wire-protocol.md` — `timestamp_ms` and `detector_latency_ms` definitions
- `protocol/skyshield-alert.schema.json` — field semantics
- `esp32-bridge/src/main.cpp` — `logAlertLatency`, points A and B
- `garmin-app/source/LatencyMonitor.mc` — points C-baseline and D
