# Garmin App

This folder contains the Garmin Connect IQ MVP prototype for SKYSHIELD.

Target device: Garmin Enduro 2.

The prototype uses hardcoded rotating mock alert data. It does not use BLE, RF detection, detector adapters, or live SKYSHIELD protocol parsing yet.

## MVP Role

The Garmin app will act as the wearable alert UI for SKYSHIELD.

Current prototype responsibilities:

- Show a tactical boot splash
- Rotate between mock FPV, DJI, and unknown threat alerts
- Alternate between ALERT, BANDS, and HISTORY screens
- Display threat type, risk level, confidence, band, distance label, and active bands
- Track the last five mock alerts in memory
- Trigger severity-based vibration patterns
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
    AlertHistory.mc
    SettingsModel.mc
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

## Current MVP Status

The MVP is a watch-only tactical UI prototype. It includes:

- Monochrome-safe tactical alert banner
- Boot splash
- Rotating mock alerts every 4 seconds
- ALERT screen for immediate action
- BANDS screen for technical signal detail
- HISTORY screen with the last five mock alerts
- Critical banner pulse
- Severity-based vibration patterns
- Simple in-app settings model for future settings UI

## Screen Cycle

After the boot splash, the app automatically cycles screens:

- `ALERT`: about 3 seconds
- `BANDS`: about 1.5 seconds
- `HISTORY`: about 1.5 seconds

Mock alerts continue rotating every 4 seconds. The screen cycle and alert rotation use separate lightweight counters so the history view can appear without slowing alert rotation.

## Alert History

`AlertHistory` stores the last five mock alerts in a fixed-size ring buffer. Each record contains:

- sequence number
- threat type
- severity
- band
- distance
- confidence

The HISTORY screen displays the newest records first using compact monochrome rows.

## Vibration Patterns

Current haptic behavior:

- `MEDIUM`: one short pulse
- `HIGH`: three short pulses
- `CRITICAL`: one long pulse, pause, then one long pulse

Vibration is controlled by `SettingsModel`:

- `vibrationEnabled`: defaults to `true`
- `sensitivity`: defaults to `NORMAL`
- `silentMode`: defaults to `false`

There is no settings screen yet. The model exists so future UI or persisted settings can wire into the same behavior.

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
- Settings are in-memory defaults only and are not user-editable yet.
- No sound behavior exists. `silentMode` is reserved for future sound-related logic.

## Future Implementation Notes

Before writing code, confirm Garmin Connect IQ support for the required BLE client behavior and haptic patterns on the Enduro 2.

Next step: implement the ESP32 BLE bridge and connect it to `AlertEngine` so `AlertModel` is populated from normalized SKYSHIELD alert payloads delivered by the ESP32-S3 bridge.
