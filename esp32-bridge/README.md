# ESP32 Bridge

This folder contains the initial ESP32-S3 firmware scaffold for the SKYSHIELD RF telemetry bridge.

The current firmware is an Arduino/PlatformIO-compatible simulated-alert prototype. It exposes simulated SKYSHIELD alert packets over Serial and a first NimBLE-based BLE GATT notify characteristic. It does not implement real RF detection yet.

## Purpose

The ESP32-S3 bridge is the RF telemetry middleware component of SKYSHIELD.

Expected long-term responsibilities:

- Generate simulated RF alerts for MVP testing
- Receive RF source events or detector-adapter telemetry in future versions
- Normalize incoming alerts into the SKYSHIELD protocol
- Assign or preserve activity level, confidence, band, and signal-strength category
- Select vibration pattern hints
- Expose current alerts over BLE

## Setup Requirements

- ESP32-S3 development board
- PlatformIO
- Arduino framework for ESP32
- NimBLE-Arduino, installed automatically by PlatformIO from `platformio.ini`
- USB serial monitor at `115200`

For first hardware setup, use the step-by-step bring-up guide:

- [ESP32-S3 Bring-Up Guide](../docs/esp32-bringup-guide.md)

Default PlatformIO environment:

```sh
pio run -e esp32-s3-devkitc-1
pio run -e esp32-s3-devkitc-1 -t upload
pio device monitor -b 115200
```

Adjust the `board` value in `platformio.ini` if using a different ESP32-S3 board.

## Wire format

The BLE alert payload is compact CBOR, specified in
[docs/wire-protocol.md](../docs/wire-protocol.md). The current
`protocol_version` is **3**. The previous pipe-delimited `S2` format is retired.

There is exactly one encoder: `include/SkyShieldCodec.h`. It is deliberately
free of any Arduino dependency so the contract test can run it natively.

## Modes

`MOCK_MODE` and `PRIORITY_TEST_MODE` in `src/main.cpp` select behavior.

`MOCK_MODE = true` rotates simulated alerts every 4 seconds, including a
data-less contact alert so the no-classification HUD path stays exercised.

`MOCK_MODE = false` (the default) runs **SERIAL_INJECT** mode. This is a bench
test-injection harness, not live detector input: an operator types one of
`FPV`, `MAVIC`, `AUTEL`, `UNKNOWN` or `CONTACT` into the serial console and the
bridge emits the corresponding alert. It was previously mislabeled "LIVE",
which implied it consumed real sensor data.

Serial output per alert shows the decoded summary and the exact bytes sent:

```text
ALERT kind=classified sensor=rf threat=FPV severity=HIGH band=5.8GHz strength=NEAR confidence=87 class=FPV seq=1 t=12840 detector_to_core=2ms
BLE TX CBOR len=41 bytes=AD010302193228030104000500060107020804090 ...
BLE notify sent
```

## BLE Server Role

The ESP32-S3 operates as the BLE server/peripheral. The Garmin Enduro 2 app will later connect as the BLE client/central and subscribe to alert notifications.

Current BLE settings:

- Advertised name: `SKYSHIELD-BRIDGE`
- Service UUID: `9f4d0001-7c31-4f9b-9a4b-8f4c0f000001`
- Alert characteristic UUID: `9f4d0002-7c31-4f9b-9a4b-8f4c0f000001`
- Alert characteristic properties: `READ`, `NOTIFY`
- Alert payload: compact Garmin-safe SKYSHIELD JSON
- BLE stack: NimBLE-Arduino

The status and config characteristics described in `docs/ble-gatt-design.md` are reserved for a later firmware step.

## BLE Test Instructions

Use a BLE scanner app such as nRF Connect or LightBlue:

1. Build and upload the firmware with PlatformIO.
2. Open the serial monitor at `115200`.
3. Confirm the boot logs include:

```text
SKYSHIELD ESP32 Bridge starting...
BLE advertising as SKYSHIELD-BRIDGE
```

4. In the BLE scanner app, scan for `SKYSHIELD-BRIDGE`.
5. Connect to the device.
6. Open service `9f4d0001-7c31-4f9b-9a4b-8f4c0f000001`.
7. Open characteristic `9f4d0002-7c31-4f9b-9a4b-8f4c0f000001`.
8. Enable notifications.
9. Verify a new compact JSON alert arrives about every 4 seconds.

Serial should also show connection events:

```text
BLE client connected
BLE client subscribed
BLE TX len=78
BLE notify sent
BLE client disconnected
```

Serial debug prints both payloads:

```text
SERIAL FULL: {"threat":"FPV",...,"bands":{...},"source":"ESP32_SIM","sequence":1}
BLE TX: {"threat":"FPV","severity":"HIGH","band":"5.8GHz","distance":"NEAR","confidence":87}
```

## Future RF Source Inputs

Potential RF source or detector-adapter integrations may include:

- Serial messages
- UDP or TCP messages
- GPIO event lines
- BLE or Wi-Fi detector feeds
- Vendor-specific APIs

Future compatibility targets include Chuyka, Tsukorok, SkyDroid, and custom RF detectors after validation work.

## Not In MVP

- Real RF scanning
- Validated direction finding
- Production detector adapters
- Garmin BLE client parsing
- Mesh networking
- Encrypted transport policy

## Limitations

- The scaffold emits simulated packets only.
- BLE is unencrypted and intended for MVP validation only.
- Only the alert characteristic is implemented.
- Signal-strength categories are not physical distance.
- Classification confidence is heuristic until validated.
- False positives and environment-specific RF behavior must be measured later.

## Validation Roadmap

Future bridge validation should include:

- Serial-to-BLE packet latency measurement
- Packet freshness and sequence behavior
- BLE stability and reconnect recovery
- False alert behavior once real RF inputs are integrated
- ESP32 battery runtime under simulated and live telemetry workloads

## Future KPIs

- Alert latency
- Packet freshness
- BLE stability
- False alert rate
- Battery runtime
- RF activity detection rate after validated RF inputs are integrated
