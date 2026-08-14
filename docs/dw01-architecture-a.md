# Architecture A — Watch Direct to DW01

**Status: prepared and dormant. No hardware has been involved.**

Architecture A is the watch connecting straight to the Tatusky DW01 over BLE,
with no ESP32 in the path. It is **not adopted**. The ESP32 chain remains the
only live source; everything here is unreachable from any active code path.

| Piece | File | State |
|---|---|---|
| Record parser | [`garmin-app/source/DW01Parser.mc`](../garmin-app/source/DW01Parser.mc) | dormant, 366 checks |
| BLE client | [`garmin-app/source/Dw01BleSource.mc`](../garmin-app/source/Dw01BleSource.mc) | dormant, 127 checks |
| Gates | `DW01_PARSER_ENABLED`, `ARCHITECTURE_A_ENABLED` | both **false** |

## Vendor-confirmed BLE parameters (Kawhi, Tatusky)

| Property | Value |
|---|---|
| Role | DW01 is the **peripheral**, watch is the **central** |
| Service | **FFE0** → `0000FFE0-0000-1000-8000-00805F9B34FB` |
| Characteristic | **FFE1** → `0000FFE1-0000-1000-8000-00805F9B34FB` |
| Delivery | **Notifications**, pushed automatically — never polled |
| Profile | Standard BLE-UART style |
| Payload | ASCII, identical to the wired format: `F5788R093T06C202` |

115200 8N1 is the DW01's own serial rate. Over BLE we consume notifications,
not a UART, so no baud is configured anywhere in the client.

## What is proven, and how

Simulator, 13 tests, **493 checks, 0 failures, 0 errors**:

- **366 checks** — the parser (vendor example, hex-not-decimal, the full type
  table, negative guardrails, C field, malformed input, and agreement with the
  C++ reference implementation's captured output)
- **127 checks** — the BLE glue, driven with injected FFE1-style `ByteArray`
  payloads: ASCII conversion, record framing, parser dispatch, counters

The glue tests cover the path from *"notification bytes arrived"* to *"an
`AlertModel` is available"*. That needs no radio, so it is genuinely verified
rather than assumed.

Notably covered: a record **split across two notifications**, tested at **every
possible byte offset** (17 split points), because a BLE-UART bridge forwards
~20-byte chunks with no framing of its own and a chunk boundary need not align
with a record boundary.

## What is NOT proven — the hardware test plan

Nothing below can be checked without the physical DW01.

### 1. Connection — does CIQ talk to FFE0/FFE1 at all?

The whole scan → connect → discover → subscribe sequence is **unexercised**.
FFE0/FFE1 is a standard, widely supported profile, so this is *likely* fine —
but likely is not verified.

- [ ] The watch sees the DW01 in a scan
- [ ] It matches on the advertised FFE0 service
- [ ] `pairDevice` connects
- [ ] `getService(FFE0)` and `getCharacteristic(FFE1)` both return non-null
- [ ] FFE1 exposes a CCCD and the subscribe write succeeds
- [ ] Notifications actually arrive

**Known gap: the advertised device name is unknown.** `DW01_DEVICE_NAME_HINT`
is deliberately **empty** and matching is by service UUID only. Inventing a name
would mean the client silently fails to match the real device. Capture the
advertised name during bring-up and fill it in as a fallback.

### 2. Connection loss — the unsolved crash class

Losing the peer crashes the app on the ESP32 path. That was never solved: the
evidence put the fault inside the CIQ BLE stack, below anything Monkey C can
guard, and six attempts to work around it either failed or destabilised normal
operation.

**Whether this persists with the DW01 as peer is UNKNOWN.** It could differ —
different peripheral, different disconnect behaviour, possibly a real
supervision-timeout callback where the ESP32 gave none (`c1 d0`).

**No loss handling is implemented here, deliberately.** `handleConnectedStateChanged`
clears its references and stops. Building speculative recovery before measuring
would repeat the exact mistake that cost the ESP32 path its stability.

- [ ] Walk out of range — does the app survive?
- [ ] Power the DW01 down cleanly — is a disconnect callback delivered?
- [ ] Abrupt power cut — callback or silence?
- [ ] If it survives: does it reconnect?

Answer these **before** writing any recovery code.

### 3. Notification rate — unstated by the vendor

Kawhi did not give a push rate. Two things depend on it:

- `DW01Parser.parseLine` allocates a char array and a dictionary **per record**
- `extractRecords` rebuilds a string per record

At a few records per second this is irrelevant. At tens per second on the
watch's memory budget it may not be. **Measure first.** The counters
(`getNotificationCount`, `getRecordCount`, `getParsedCount`) exist for exactly
this and are cheap to read during bring-up.

- [ ] Records per second, idle and with a drone present
- [ ] Bytes per notification (confirms the ~20-byte chunking assumption)
- [ ] Whether records are CR/LF terminated or run together
- [ ] Watch memory over a sustained session

Do **not** add buffering or throttling before there are numbers.

### 4. Framing — an assumption, not a fact

`extractRecords` handles both framings without preferring either:

- if the device terminates records (CR and/or LF), split on that
- otherwise split before each subsequent `F`, since every record starts with one

Splitting on `F` rather than a fixed 16-byte width is deliberate: **the C
field's length is not specified by the vendor**, so assuming a total record
length would be a guess. The trailing segment is always held back for the next
notification.

A runaway stream that never yields a record is dropped at
`DW01_RX_BUFFER_LIMIT` (200 bytes) rather than growing without bound, and the
client recovers afterwards — both tested.

- [ ] Confirm the real framing against captured traffic

## One-delegate constraint

Connect IQ allows **one BLE delegate per app**. `Dw01BleSource.start()` calls
`Ble.setDelegate`, which would displace `BleAlertSource`'s.

The two sources are therefore **mutually exclusive by construction**. That is
correct — Architecture A means the ESP32 is not in the path — but they can never
run side by side, so a future switch must stop one before starting the other.

## Switching it on, when the time comes

Nothing today references either class. Enabling Architecture A means:

1. `ARCHITECTURE_A_ENABLED = true` and `DW01_PARSER_ENABLED = true`
2. Stop `BleAlertSource` before starting `Dw01BleSource` (one-delegate rule)
3. Point `AlertEngine` at the new source — it exposes the same
   `getNextAlert()` / `getLatestAlert()` / `hasLatestAlert()` surface
4. Fill in `DW01_DEVICE_NAME_HINT` once the advertised name is known

Steps 2 and 3 touch the active path and are **not** done. They wait on the
device.

## Deliberately not built

- Connection-loss handling — see §2
- Reconnect or backoff
- Any buffering or throttling — see §3
- Any wiring into `AlertEngine`
- Any change to the CBOR decoder, which Architecture A does not use at all:
  the DW01 speaks ASCII directly, so there is no CBOR in this path
