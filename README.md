# SKYSHIELD

SKYSHIELD is a wearable RF situational awareness platform for field RF monitoring workflows. It connects simulated or external RF activity sources to a Garmin Enduro 2 wearable interface through an ESP32-S3 bridge.

The system receives RF telemetry-style alert events, normalizes them into a compact BLE payload, and delivers concise RF awareness cues to a Garmin watch with clear text, deterministic screen flow, and vibration patterns.

## Project Status

The current MVP baseline is functional:

- Garmin tactical HUD MVP is functional.
- ESP32-to-Garmin BLE S2 payload pipeline works.
- Garmin app renders live tactical alerts from BLE notifications.
- The ALERT UI includes:
  - drone classification top field
  - RF threat type
  - primary band
  - signal strength
  - left RF band activity
  - right severity gauge
  - `LIVE` / `RX` footer

The current watch UI is an RF situational awareness HUD, not a validated drone detector or targeting system.

## Architecture

```text
Drone Detector -> Middleware / ESP32 Bridge -> BLE S2 payload -> Garmin HUD
```

Responsibilities:

Detector:

- RF detection
- vendor, protocol, or drone classification

Middleware / ESP32:

- telemetry normalization
- payload generation
- BLE transmission

Garmin:

- payload parsing
- HUD rendering
- haptics
- deterministic ALERT/BANDS cycle

## Project Roles

- External RF sources or future detector adapters are the sensor layer.
- ESP32-S3 is the middleware bridge, BLE server, and telemetry processor.
- Garmin Enduro 2 is the wearable RF HUD and vibration alert device.

The Garmin watch does not perform RF detection. The ESP32-S3 does not replace specialized RF hardware. SKYSHIELD sits between RF telemetry sources and field operators.

## Payload

The current BLE baseline is documented in [PAYLOAD_SPEC.md](PAYLOAD_SPEC.md).

Current wire format:

```text
S2|RF_TYPE|SEVERITY|BAND|STRENGTH|DRONE_CLASS
```

Examples:

```text
S2|F|H|58|N|FPV
S2|D|M|24|M|MAVIC
S2|U|C|X|N|UNKNOWN
S2|D|M|24|M|AUTEL
```

The S2 payload intentionally does not include a confidence percentage. Drone classification comes from the upstream detector or middleware layer and is rendered as the top field on the Garmin ALERT screen.

## MVP Focus

The first MVP uses simulated RF alerts rather than real RF sensing. It validates the protocol, BLE transport assumptions, packet freshness handling, Garmin HUD flow, and vibration behavior.

MVP alert fields:

- Signal classification
- RF activity level
- Drone classification
- Frequency band
- Signal-strength category
- Vibration pattern
- BLE transport payload

Direction estimation, live RF processing, detector-specific integrations, AI/prediction, triangulation, and command/control features are long-term research directions, not near-term validated capabilities.

## Limitations

- RSSI and band activity are not precise physical distance measurements.
- RF classification is heuristic until validated against field data.
- False positives and false negatives are expected in complex RF environments.
- RF conditions vary heavily by terrain, antenna orientation, interference, and body position.
- Direction estimation is experimental and should be treated as an operator cue, not a precise bearing.
- The current MVP uses simulated packets and does not validate real RF detection performance.

## Detection Validation

Future validation work should measure RF awareness performance before making stronger detection claims:

- Controlled field testing with repeatable scenarios
- Urban RF testing with dense interference
- Open-field testing with lower background noise
- DJI experiments and controlled known-device trials where lawful and safe
- False positive measurement across common RF sources
- End-to-end latency measurement from packet generation to watch display/vibration
- Battery runtime measurement for Garmin and ESP32 operating modes

## Future KPIs

- Alert latency from bridge packet to watch HUD update
- Packet freshness and stale-packet rate
- BLE connection stability and reconnect recovery time
- False alert rate during representative RF background activity
- Battery runtime for the ESP32 bridge and watch app
- RF activity detection rate after real RF inputs are integrated and validated

## Repository Structure

```text
SKYSHIELD/
  docs/
    product-vision.md
    mvp-scope.md
    ble-protocol.md
    garmin-ui.md
    hardware-notes.md
  garmin-app/
    README.md
  esp32-bridge/
    README.md
  protocol/
    skyshield-alert.schema.json
    examples/
      fpv-high.json
      dji-low.json
      unknown-critical.json
  mock-data/
    alert-scenarios.json
  tools/
    README.md
```

## Build Instructions

Garmin:

```sh
cd garmin-app
"/Users/milankrcho/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeyc" -f monkey.jungle -o skyshield.prg -y ../developer_key
```

ESP32:

Use VSCode PlatformIO:

- open `esp32-bridge`
- Build
- Upload
- Monitor

## Compatibility Targets

Future RF source compatibility targets include:

- Chuyka
- Tsukorok
- SkyDroid
- Custom RF detectors

These targets are not part of the first simulated-alert MVP and require validation before any detection-performance claims.

## Notes

- Confidence percentage was removed from the BLE S2 payload and Garmin ALERT screen intentionally.
- Garmin must not invent fake telemetry.
- No fake radar, fake direction, or fake confidence should be displayed.
- Generated build files are ignored by git.
- Real RF sensing and detector adapter validation are not complete.
