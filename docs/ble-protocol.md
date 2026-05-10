# BLE Protocol

The MVP assumes the ESP32-S3 acts as a BLE server and the Garmin Enduro 2 Connect IQ app acts as a BLE client.

The BLE link transports normalized SKYSHIELD alert payloads from the ESP32-S3 bridge to the watch.

## Roles

- ESP32-S3: BLE peripheral/server
- Garmin Enduro 2: BLE central/client
- Drone detectors: external sensor inputs to the bridge

## MVP Transport Strategy

The MVP should transmit compact JSON alert payloads that conform to `protocol/skyshield-alert.schema.json`.

The exact BLE service UUIDs and characteristic UUIDs are reserved for implementation. Documentation should be updated before firmware or watch code is written.

## Proposed GATT Shape

Service:

- Name: SKYSHIELD Alert Service
- Purpose: Alert delivery from bridge to watch

Characteristics:

- Alert Notify Characteristic
  - Direction: ESP32-S3 to Garmin
  - Mode: notify
  - Payload: UTF-8 JSON

- Status Characteristic
  - Direction: Garmin to ESP32-S3 or read by Garmin
  - Mode: read/write
  - Payload: short status JSON

## Alert Delivery Behavior

The ESP32-S3 should notify the Garmin app when a new alert arrives or when a higher priority alert supersedes an active one.

Recommended behavior:

- Send critical alerts immediately.
- Avoid repeatedly sending identical low-risk alerts.
- Include `expires_in_ms` so the watch can clear stale alerts.
- Keep payloads small enough for BLE fragmentation constraints.

## Reliability Assumptions

BLE transport is local and opportunistic. The watch UI should tolerate missed alerts, duplicate alerts, and reconnect events.

The ESP32-S3 should maintain a short recent-alert cache so the Garmin app can recover current state after reconnecting.

## Not In MVP

- Encrypted pairing policy
- Multi-watch broadcast
- Mesh forwarding
- Binary payload encoding
- Firmware over-the-air update
