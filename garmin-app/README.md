# Garmin App

This folder contains the first Garmin Connect IQ MVP skeleton for SKYSHIELD.

Target device: Garmin Enduro 2.

The prototype uses hardcoded mock alert data. It does not use BLE, RF detection, detector adapters, or live SKYSHIELD protocol parsing yet.

## MVP Role

The Garmin app will act as the wearable alert UI for SKYSHIELD.

Current prototype responsibilities:

- Show one tactical mock alert
- Display threat type, risk level, confidence, band, distance label, and active bands
- Trigger a simple vibration for high or critical alerts
- Use high-contrast text for the Garmin Enduro 2 MIP display

Future responsibilities:

- Connect to the ESP32-S3 bridge over BLE
- Receive normalized SKYSHIELD alert payloads
- Validate or safely parse alert fields from the shared protocol
- Display tactical warning information
- Trigger vibration patterns based on risk level
- Clear or downgrade expired alerts

## Folder Structure

```text
garmin-app/
  manifest.xml
  monkey.jungle
  source/
    SkyShieldApp.mc
    SkyShieldView.mc
    AlertModel.mc
    AlertEngine.mc
    VibrationEngine.mc
    MockAlertProvider.mc
  resources/
    strings/
      strings.xml
```

## Build and Run

Prerequisites:

- Garmin Connect IQ SDK installed
- Garmin Connect IQ simulator installed
- Enduro 2 device profile available in the SDK

Typical local workflow:

```sh
cd SKYSHIELD/garmin-app
monkeyc -f monkey.jungle -o bin/SKYSHIELD.prg -y developer_key.der -d enduro2
monkeydo bin/SKYSHIELD.prg enduro2
```

The exact SDK commands may vary by local Garmin SDK installation and developer key path.

## Not Responsible For

- Drone detection
- RF processing
- Direction finding
- Detector-specific parsing
- Alert normalization

Those responsibilities belong to the detector layer or ESP32-S3 bridge.

## Current Limitations

- Mock alert data is hardcoded in `source/MockAlertProvider.mc`.
- BLE integration is intentionally not implemented.
- Alert JSON schema validation is not implemented on the watch.
- Vibration behavior must be validated on Garmin hardware or simulator support.
- UI is a minimal single-screen prototype, not a production interaction model.

## Future Implementation Notes

Before writing code, confirm Garmin Connect IQ support for the required BLE client behavior and haptic patterns on the Enduro 2.

BLE integration should be added around `AlertEngine` and should populate `AlertModel` from normalized SKYSHIELD alert payloads delivered by the ESP32-S3 bridge.
