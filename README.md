# SKYSHIELD

SKYSHIELD is a tactical drone alert middleware project for field warning workflows. It connects existing drone detector systems to a Garmin Enduro 2 wearable interface through an ESP32-S3 bridge.

The system receives detector alerts, normalizes them into a universal alert protocol, and delivers concise tactical warnings to a Garmin watch with clear text, risk indication, and vibration patterns.

## Project Roles

- Existing drone detectors are the sensor layer.
- ESP32-S3 is the middleware bridge, BLE server, and alert processor.
- Garmin Enduro 2 is the wearable UI and vibration alert device.

The Garmin watch does not perform RF detection. The ESP32-S3 does not replace specialized drone detectors. SKYSHIELD sits between detector outputs and field operators.

## MVP Focus

The first MVP uses simulated alerts rather than real RF detection. It validates the protocol, BLE transport assumptions, alert prioritization, Garmin UI flow, and vibration behavior.

MVP alert fields:

- Threat type
- Risk level
- Confidence score
- Frequency band
- Distance category
- Vibration pattern
- BLE transport payload

Direction finding, live RF processing, detector-specific integrations, and command/control features are future work.

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

## Compatibility Targets

Future detector compatibility targets include:

- Chuyka
- Tsukorok
- SkyDroid
- Custom RF detectors

These targets are not part of the first simulated-alert MVP.

## Status

Initial documentation and protocol scaffold only. No production firmware, Garmin app code, or detector integration code has been added yet.
