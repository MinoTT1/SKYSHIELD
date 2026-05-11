# Garmin App

This folder contains the Garmin Connect IQ MVP prototype for SKYSHIELD.

Target device: Garmin Enduro 2.

The prototype uses hardcoded rotating mock alert data. It does not use BLE, RF detection, detector adapters, or live SKYSHIELD protocol parsing yet.

## MVP Role

The Garmin app will act as the wearable RF HUD for SKYSHIELD.

Current prototype responsibilities:

- Show a tactical boot splash
- Rotate between mock FPV, DJI, and unknown threat alerts
- Alternate automatically between ALERT and BANDS screens
- Display threat type, RF activity level, band, signal-strength label, confidence, action state, and active bands
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
- Display RF situational awareness information
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
- RF action state on the ALERT screen for immediate field awareness
- Centralized tactical action mapping in `TacticalActionEngine`
- Compact system-health metadata on the ALERT screen
- Boot splash
- Rotating mock alerts every 4 seconds
- ALERT screen for RF situational awareness
- BANDS screen for technical signal detail
- HISTORY screen implementation retained for manual/debug use
- Garmin-side parser for the canonical SKYSHIELD JSON packet
- AlertSource abstraction for swapping mock data with future BLE data
- Simulated BLE lifecycle state tracking
- Elevated RF activity banner pulse
- Severity-based vibration patterns
- Simple in-app settings model for future settings UI

## Screen Cycle

After the boot splash, the app automatically cycles screens:

- `ALERT`: 8 seconds
- `BANDS`: 1.5 seconds

Mock alerts continue rotating every 4 seconds. The screen cycle and alert rotation use separate lightweight elapsed-time counters so ALERT remains the primary field view and BANDS remains the secondary technical view.

If a new mock alert arrives while BANDS is visible, the HUD returns to ALERT. The HISTORY screen remains implemented in code, but it is not part of the automatic field rotation.

## Alert History

`AlertHistory` stores the last five mock alerts in a fixed-size ring buffer. Each record contains:

- sequence number
- threat type
- severity
- band
- RF signal-strength category
- confidence

The HISTORY screen displays the newest records first using compact monochrome rows.

## Action State

`TacticalActionEngine` keeps the bottom action label credibility-safe for the MVP:

- Any active RF packet: `MONITOR`
- Connection `SIGNAL_LOST`: `NO RF LINK`

The protocol still uses `CRITICAL`, `NEAR`, `MID`, and `FAR`, but the Garmin HUD translates these user-facing labels:

- `CRITICAL`: `ELEVATED`
- `NEAR`: `STRONG`
- `MID`: `MODERATE`
- `FAR`: `WEAK`

This keeps the primary ALERT screen focused on RF situational awareness, while BANDS remains available for supporting detail. HISTORY is retained in code for future manual/debug access but is not part of the automatic field cycle.

The ALERT screen visual priority is:

1. action
2. severity
3. threat type
4. signal strength
5. band
6. direction
7. confidence
8. system-health metadata

`MONITOR` is intentionally calm and compact. Confidence is displayed on the ALERT screen so the HUD does not imply absolute certainty.

## System Health Metadata

The ALERT screen includes a tiny gray metadata line for operator trust:

- RF activity: `TRACK` for recent packets, `SCAN` after stale packets, `IDLE` after a longer quiet period.

Packet age and BLE health are still tracked internally for future display, but the ALERT screen currently renders only the RF activity state to avoid clutter on the round Garmin display. This line is intentionally subtle and does not compete with the main alert or action state.

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

The simulated connection state still runs internally, but the top metadata label is not rendered on the ALERT screen. The HUD prioritizes RF activity, signal strength, confidence, and action state over connection plumbing.

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

- RF detection or raw spectrum processing
- Validated RF classification
- Precise direction finding
- Detector-specific parsing
- Alert normalization

Those responsibilities belong to future RF source adapters, detector hardware, or the ESP32-S3 bridge.

## Current Limitations

- Mock alert JSON strings are hardcoded in `source/MockAlertSource.mc`.
- BLE integration is intentionally not implemented.
- Alert JSON schema validation is not implemented on the watch.
- Vibration behavior must be validated on Garmin hardware or simulator support.
- Settings are in-memory defaults only and are not user-editable yet.
- No sound behavior exists. `silentMode` is reserved for future sound-related logic.
- RSSI-like signal strength is not precise physical distance.
- Direction hints are simulated/experimental until validated.
- Classification confidence is heuristic in the MVP.

## Validation Roadmap

Future Garmin validation should include:

- Packet-to-HUD latency measurement
- Packet freshness and stale state behavior
- BLE reconnect behavior
- Vibration latency and perceived clarity
- Watch battery runtime during long monitoring sessions

## Future KPIs

- Alert packet-to-HUD latency
- Stale packet rate
- BLE reconnect success rate
- Vibration delivery reliability
- Watch battery runtime
- Operator readability in simulated field scenarios

## Future Implementation Notes

Before writing code, confirm Garmin Connect IQ support for the required BLE client behavior and haptic patterns on the Enduro 2.

Next step: implement the ESP32 BLE bridge and replace `MockAlertSource` with `BleAlertSource` so `AlertModel` is populated from normalized SKYSHIELD alert payloads delivered by the ESP32-S3 bridge.
