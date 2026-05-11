# BLE Protocol

The MVP assumes the ESP32-S3 acts as a BLE server and the Garmin Enduro 2 Connect IQ app acts as a BLE client.

The BLE link will transport canonical SKYSHIELD alert packets from the ESP32-S3 bridge to the watch. The same JSON packet is currently emitted over Serial by the ESP32 simulated bridge.

For the planned service and characteristic layout, see `docs/ble-gatt-design.md`.

## Roles

- ESP32-S3: BLE peripheral/server and alert bridge
- Garmin Enduro 2: BLE central/client and wearable RF HUD
- RF telemetry sources or future detector adapters: external sensor inputs to the bridge in future versions

## Canonical Alert Packet

All SKYSHIELD bridge-to-watch alerts must conform to `protocol/skyshield-alert.schema.json`.

Required fields:

- `threat`: `FPV`, `DJI`, or `UNKNOWN`
- `severity`: `LOW`, `MEDIUM`, `HIGH`, or `CRITICAL`
- `band`: `1.2GHz`, `2.4GHz`, `3.3GHz`, `5.8GHz`, or `MULTI`
- `distance`: `FAR`, `MID`, or `NEAR`
- `confidence`: integer from `0` to `100`

Optional fields:

- `direction`: `FRONT`, `LEFT`, `RIGHT`, or `REAR`
- `bands`: object with `band_1_2`, `band_2_4`, `band_3_3`, and `band_5_8`
- `source`: source label such as `ESP32_SIM`
- `sequence`: bridge-generated packet sequence number

Band strength values are:

- `LOW`
- `MED`
- `HIGH`
- `NONE`

Note: the `distance` field is a legacy protocol term for coarse RF signal-strength category. Garmin UI should display `FAR` as `WEAK`, `MID` as `MODERATE`, and `NEAR` as `STRONG`. RSSI-like values are not precise physical distance measurements.

Example:

```json
{"threat":"FPV","severity":"HIGH","band":"5.8GHz","direction":"FRONT","distance":"NEAR","confidence":87,"bands":{"band_1_2":"LOW","band_2_4":"LOW","band_3_3":"MED","band_5_8":"HIGH"},"source":"ESP32_SIM","sequence":1}
```

## Current Serial Mock Mode

The first ESP32 bridge scaffold does not use BLE yet. It emits the same canonical JSON packet over Serial every 4 seconds.

This lets the team validate packet shape, sequence behavior, mock alert rotation, freshness handling, and Garmin-side parsing assumptions before BLE transport is added.

## Future BLE GATT Shape

Service:

- Name: SKYSHIELD Alert Service
- Purpose: Alert delivery from bridge to watch

Characteristics:

- Alert Notify Characteristic
  - Direction: ESP32-S3 to Garmin
  - Mode: notify
  - Payload: UTF-8 JSON using the canonical alert packet

- Status Characteristic
  - Direction: Garmin to ESP32-S3 or read by Garmin
  - Mode: read/write
  - Payload: short status JSON

The Garmin app will later parse the same JSON payload currently printed by the ESP32 Serial mock mode.

## Alert Delivery Behavior

The ESP32-S3 should notify the Garmin app when a new RF telemetry event arrives or when a higher-priority RF activity cue supersedes an active one.

Recommended behavior:

- Send elevated RF activity immediately.
- Avoid repeatedly sending identical low-risk alerts.
- Include `sequence` so the watch can ignore duplicate packets.
- Keep payloads small enough for BLE notification constraints.

## Reliability Assumptions

BLE transport is local and opportunistic. The watch UI should tolerate missed alerts, duplicate alerts, and reconnect events.

The ESP32-S3 should maintain a short recent-alert cache so the Garmin app can recover current state after reconnecting.

## Not In MVP

- Garmin BLE parsing in the current app
- Encrypted pairing policy
- Multi-watch broadcast
- Mesh forwarding
- Binary payload encoding
- Firmware over-the-air update

## Limitations

- BLE payload delivery does not validate RF detection accuracy.
- The `confidence` value is source-provided or heuristic until validated.
- The `distance` field is not physical range.
- Direction values are optional and experimental.

## Validation And KPIs

Future validation should measure:

- Packet latency from ESP32 generation to Garmin display
- Packet freshness and stale packet behavior
- BLE stability and reconnect behavior
- False alert rate once real RF inputs are integrated
- Battery runtime under simulated and live telemetry workloads
