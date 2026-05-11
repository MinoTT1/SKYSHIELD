# Garmin App

This folder contains the Garmin Connect IQ MVP prototype for SKYSHIELD.

Target device: Garmin Enduro 2.

The prototype uses hardcoded rotating mock alert data. It does not use BLE, RF detection, detector adapters, or live SKYSHIELD protocol parsing yet.

## MVP Role

The Garmin app will act as the wearable alert UI for SKYSHIELD.

Current prototype responsibilities:

- Show a tactical boot splash
- Rotate between mock FPV, DJI, and unknown threat alerts
- Alternate automatically between ALERT and BANDS screens
- Display threat type, risk level, band, distance label, action state, and active bands
- Track the last five mock alerts in memory
- Parse canonical SKYSHIELD JSON alert packets into Garmin alert models
- Show optional simulated direction hints on the ALERT screen
- Simulate BLE connection lifecycle states on the HUD
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
    AlertParser.mc
    AlertEngine.mc
    TacticalActionEngine.mc
    AlertSource.mc
    MockAlertSource.mc
    BleAlertSource.mc
    ConnectionStateService.mc
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
- ACTION state on the ALERT screen for immediate field response
- Centralized tactical action mapping in `TacticalActionEngine`
- Boot splash
- Rotating mock alerts every 4 seconds
- ALERT screen for immediate action
- BANDS screen for technical signal detail
- HISTORY screen implementation retained for manual/debug use
- Garmin-side parser for the canonical SKYSHIELD JSON packet
- AlertSource abstraction for swapping mock data with future BLE data
- Simulated BLE lifecycle state display
- Critical banner pulse
- Severity-based vibration patterns
- Simple in-app settings model for future settings UI

## Screen Cycle

After the boot splash, the app automatically cycles screens:

- `ALERT`: 8 seconds
- `BANDS`: 1.5 seconds

Mock alerts continue rotating every 4 seconds. The screen cycle and alert rotation use separate lightweight elapsed-time counters so ALERT remains the primary field view and BANDS remains the secondary technical view.

Each new mock alert immediately returns the HUD to ALERT. The HISTORY screen remains implemented in code, but it is not part of the automatic field rotation.

## Alert History

`AlertHistory` stores the last five mock alerts in a fixed-size ring buffer. Each record contains:

- sequence number
- threat type
- severity
- band
- distance
- confidence

The HISTORY screen displays the newest records first using compact monochrome rows.

## Action State

`TacticalActionEngine` maps severity and distance into a compact operator action:

- `CRITICAL` + `NEAR`: `TAKE COVER`
- `CRITICAL` + `MID` or `FAR`: `ALERT`
- `HIGH` + `NEAR`: `TAKE COVER`
- `HIGH` + `MID` or `FAR`: `ALERT`
- `MEDIUM` or `LOW`: `MONITOR`
- Connection `SIGNAL LOST`: `SIGNAL LOST`

This keeps the primary ALERT screen focused on what the user should do next, while BANDS remains available for supporting detail. HISTORY is retained in code for future manual/debug access but is not part of the automatic field cycle.

The ALERT screen visual priority is:

1. action
2. severity
3. threat type
4. distance
5. band
6. direction
7. connection metadata

`TAKE COVER` receives the strongest bottom-screen emphasis, `ALERT` uses medium emphasis, and `MONITOR` is intentionally quieter.

## Protocol Parser

`AlertParser` converts the canonical SKYSHIELD JSON payload into the Garmin `AlertModel`.

Current mock alerts are stored as local JSON strings in `MockAlertSource` and parsed through this same parser.

## AlertSource Architecture

`AlertEngine` depends on an AlertSource-style object with a simple `getNextAlert()` method.

Current flow:

```text
MockAlertSource -> AlertParser -> AlertModel -> AlertEngine -> SkyShieldView
```

Future BLE flow:

```text
BleAlertSource -> AlertParser -> AlertModel -> AlertEngine -> SkyShieldView
```

`BleAlertSource` is a placeholder only. It documents where the future ESP32 BLE notify payload will be received and passed into `AlertParser.parse()`.

## Simulated BLE Lifecycle

The HUD shows a very small monochrome connection state:

- `scan`: scanning
- `conn`: connecting
- `ok`: connected
- `lost`: signal lost

Current simulated flow:

```text
SCANNING (~3s) -> CONNECTING (~2s) -> CONNECTED -> SIGNAL LOST (~2s blink) -> CONNECTING -> CONNECTED
```

`ConnectionStateService` drives this simulation with the existing lightweight timer. Future BLE callbacks can update this same state service from real scan, connect, disconnect, and reconnect events.

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

- Mock alert JSON strings are hardcoded in `source/MockAlertSource.mc`.
- BLE integration is intentionally not implemented.
- Alert JSON schema validation is not implemented on the watch.
- Vibration behavior must be validated on Garmin hardware or simulator support.
- Settings are in-memory defaults only and are not user-editable yet.
- No sound behavior exists. `silentMode` is reserved for future sound-related logic.

## Future Implementation Notes

Before writing code, confirm Garmin Connect IQ support for the required BLE client behavior and haptic patterns on the Enduro 2.

Next step: implement the ESP32 BLE bridge and replace `MockAlertSource` with `BleAlertSource` so `AlertModel` is populated from normalized SKYSHIELD alert payloads delivered by the ESP32-S3 bridge.
