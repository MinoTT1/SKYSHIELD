# BLE GATT Design

This document defines the planned BLE GATT integration between the ESP32-S3 SKYSHIELD Bridge and the Garmin watch app.

No BLE implementation is included yet. This is the design contract for the next firmware and Garmin integration step.

## BLE Device

- Advertised name: `SKYSHIELD-BRIDGE`
- ESP32-S3 role: BLE peripheral/server
- Garmin role: BLE central/client

The ESP32 Bridge owns alert generation, normalization, and BLE notification. The Garmin app subscribes to alerts and renders the tactical HUD.

## GATT Service

Placeholder UUIDs are fixed for MVP development and may be replaced before production.

- SKYSHIELD Alert Service UUID: `9f4d0001-7c31-4f9b-9a4b-8f4c0f000001`
- Alert Characteristic UUID: `9f4d0002-7c31-4f9b-9a4b-8f4c0f000001`
- Status Characteristic UUID: `9f4d0003-7c31-4f9b-9a4b-8f4c0f000001`
- Config Characteristic UUID: `9f4d0004-7c31-4f9b-9a4b-8f4c0f000001`

## Alert Characteristic

Properties:

- `notify`

Payload:

- UTF-8 string
- Canonical SKYSHIELD JSON alert packet
- One alert per notification

Packet strategy:

- Keep JSON compact.
- Use canonical field names from `protocol/skyshield-alert.schema.json`.
- Send one complete alert per notification.
- If packet size becomes too large later, add explicit chunking rather than partial ad hoc messages.

Example payload:

```json
{"threat":"FPV","severity":"HIGH","band":"5.8GHz","direction":"FRONT","distance":"NEAR","confidence":87,"bands":{"band_1_2":"LOW","band_2_4":"LOW","band_3_3":"MED","band_5_8":"HIGH"},"source":"ESP32_SIM","sequence":1}
```

## Status Characteristic

Properties:

- `read`
- optional future `notify`

Status payload should be compact JSON.

Suggested fields:

- `battery`: bridge battery percentage, integer `0-100`
- `state`: `BOOT`, `READY`, `ALERTING`, `ERROR`
- `detector`: `SIMULATED`, `CONNECTED`, `DISCONNECTED`
- `uptime_ms`: bridge uptime in milliseconds

Example:

```json
{"battery":92,"state":"READY","detector":"SIMULATED","uptime_ms":12000}
```

## Config Characteristic

Properties:

- `read`
- `write`

Config payload should be compact JSON.

Suggested fields:

- `sensitivity`: `LOW`, `NORMAL`, `HIGH`
- `vibration_profile`: `STANDARD`, `AGGRESSIVE`, `SILENT`
- `mode`: `SIM`, `DETECTOR`, `RF`

Example:

```json
{"sensitivity":"NORMAL","vibration_profile":"STANDARD","mode":"SIM"}
```

MVP config writes can be ignored until firmware settings are implemented, but the characteristic shape should be reserved early.

## Garmin Flow

Planned Garmin app flow:

1. Scan for BLE devices advertising `SKYSHIELD-BRIDGE`.
2. Connect as BLE central/client.
3. Discover the SKYSHIELD Alert Service.
4. Subscribe to the Alert Characteristic.
5. Receive UTF-8 JSON alert payloads.
6. Pass each JSON string to `AlertParser.parse()`.
7. Update `AlertModel`.
8. Refresh the tactical HUD, history, and vibration behavior.

Garmin BLE parsing is not implemented in the current MVP.

## ESP32 Flow

Planned ESP32 bridge flow:

1. Generate simulated alert or receive detector alert.
2. Normalize alert to the canonical SKYSHIELD JSON packet.
3. Print the same JSON over Serial for debugging.
4. Notify the Alert Characteristic with the UTF-8 JSON payload.
5. Update Status Characteristic state as needed.

The Serial mock mode remains useful for debugging even after BLE is added.

## MVP Limits

- No encryption yet.
- One Garmin client.
- Short compact JSON only.
- Simulator-first workflow.
- No chunking in the first BLE implementation.
- No real RF direction finding yet.

## Future Work

- Pairing and security policy
- Packet chunking for larger payloads
- Multiple Garmin clients
- Detector adapter framework
- LoRa relay or field relay mode
- Persistent bridge configuration
- Direction-finding payload refinement
