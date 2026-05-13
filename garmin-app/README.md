# Garmin App

This folder contains the Garmin Connect IQ MVP prototype for SKYSHIELD.

Target device: Garmin Enduro 2.

The prototype uses hardcoded rotating mock alert data with a first Garmin BLE source skeleton prepared for ESP32 notifications. It does not use real RF detection or detector adapters yet.

## MVP Role

The Garmin app will act as the wearable RF HUD for SKYSHIELD.

Current prototype responsibilities:

- Show a tactical boot splash
- Rotate between mock FPV, DJI, and unknown threat alerts
- Alternate automatically between ALERT and BANDS screens
- Display threat type, RF activity level, band, signal-strength label, confidence, action state, and active bands
- Translate protocol terminology into credibility-safe RF awareness wording on the HUD
- Show lightweight track stability and packet freshness metadata
- Track the last five mock alerts in memory
- Parse canonical SKYSHIELD JSON alert packets into Garmin alert models
- Prepare a BLE source for the ESP32 `SKYSHIELD-BRIDGE` notify characteristic
- Preserve protocol direction fields for future research, but do not display direction on the HUD
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
    DisplayFormatter.mc
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
- Centralized HUD label mapping in `DisplayFormatter`
- Compact system-health metadata on the ALERT screen
- Track stability labels for transient, stable, and locked RF activity
- Boot splash
- BLE validation mode with mock fallback disabled by default
- ALERT screen for RF situational awareness
- BANDS screen for technical signal detail
- HISTORY screen implementation retained for manual/debug use
- Garmin-side parser for the canonical SKYSHIELD JSON packet
- AlertSource abstraction for swapping mock data with future BLE data
- BLE source with Connect IQ scan/connect/subscribe/notification wiring and mock fallback
- Simulated BLE lifecycle state tracking
- Elevated RF activity banner pulse
- Severity-based vibration patterns
- Simple in-app settings model for future settings UI

## Screen Cycle

After the boot splash, the app automatically cycles screens:

- `ALERT`: 8 seconds
- `BANDS`: 1.5 seconds

The alert poll interval remains 4 seconds. In BLE validation mode, the HUD updates from received BLE packets only. If mock fallback is enabled for simulator/demo work, mock alerts rotate on that same interval. The screen cycle and alert polling use separate lightweight elapsed-time counters so ALERT remains the primary field view and BANDS remains the secondary technical view.

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

The protocol still uses `CRITICAL`, `NEAR`, `MID`, `FAR`, and `MULTI`, but the Garmin HUD translates these user-facing labels through `DisplayFormatter`:

- `CRITICAL`: `ELEVATED`
- `NEAR`: `STRONG`
- `MID`: `MODERATE`
- `FAR`: `WEAK`
- `MULTI`: `MULTI RF`

`DisplayFormatter` is the single source of truth for user-facing HUD labels. Parser and protocol enums remain unchanged internally. This keeps the primary ALERT screen focused on RF situational awareness, while BANDS remains available for supporting detail. HISTORY is retained in code for future manual/debug access but is not part of the automatic field cycle.

The ALERT screen top-to-bottom order is:

1. system-health metadata, tiny and gray
2. RF activity level
3. threat type
4. confidence
5. band
6. signal strength
7. action state

The metadata remains visually secondary despite appearing first. `MONITOR` is intentionally calm and compact. Confidence is displayed on the ALERT screen so the HUD does not imply absolute certainty.

## System Health Metadata

The ALERT screen includes a tiny gray metadata line for operator trust:

- `TRANSIENT`: short-duration or low-confidence RF activity
- `STABLE`: repeated same threat and band
- `LOCKED`: repeated same threat and band with confidence of 90% or higher
- `STALE`: packet freshness exceeds 10 seconds
- `SCAN`: no active alert model is available

BLE connection state is still simulated internally for future integration, but the ALERT screen does not render long BLE strings. This keeps the metadata compact on the round Garmin display and avoids presenting the MVP as a validated detector.

## Severity Scoring

`DisplayFormatter` resolves display severity from the parsed protocol severity plus RF context:

- parsed `CRITICAL` remains user-facing `ELEVATED`
- parsed `HIGH` remains `HIGH`
- `MULTI` band with confidence of 70% or higher resolves to `ELEVATED`
- `LOCKED` strong RF activity resolves to `ELEVATED`
- `LOCKED` activity never resolves to `LOW`
- FPV with confidence of 80% or higher resolves to `HIGH`
- DJI with confidence of 70% or higher resolves to `MEDIUM`
- `LOW` is reserved for weak, low-confidence, or fallback RF activity

## Protocol Parser

`AlertParser` converts the canonical SKYSHIELD JSON payload into the Garmin `AlertModel`.

Current mock alerts are stored as local JSON strings in `MockAlertSource` and parsed through this same parser.

## AlertSource Architecture

`AlertEngine` depends on an AlertSource-style object with a simple `getNextAlert()` method.

Current runtime flow:

```text
BleAlertSource -> AlertParser -> AlertModel -> AlertEngine -> SkyShieldView
     |
     +-- falls back to MockAlertSource when no BLE packet is available
```

Mock fallback flow:

```text
MockAlertSource -> AlertParser -> AlertModel -> AlertEngine -> SkyShieldView
```

`BleAlertSource` contains the fixed ESP32 BLE contract and Connect IQ central/client flow:

- Advertised name: `SKYSHIELD-BRIDGE`
- Service UUID: `9f4d0001-7c31-4f9b-9a4b-8f4c0f000001`
- Alert characteristic UUID: `9f4d0002-7c31-4f9b-9a4b-8f4c0f000001`
- Payload: UTF-8 canonical SKYSHIELD JSON

Implemented BLE lifecycle states:

- `SCANNING`
- `CONNECTING`
- `CONNECTED`
- `DISCONNECTED`
- `SIGNAL_LOST`

The Garmin app registers the SKYSHIELD service profile, scans for peripherals advertising the SKYSHIELD service UUID, pairs with the matching peripheral, discovers the alert service and characteristic, writes the CCCD to enable notifications, decodes UTF-8 notification payloads, and passes each JSON string to `AlertParser.parse()`.

## Source Modes

`AlertEngine` exposes the current alert source:

- `BLE`: a parsed ESP32 BLE packet is currently driving the HUD
- `MOCK`: simulator/demo fallback is driving the HUD
- `NONE`: no BLE packet is available and mock fallback is disabled

`USE_MOCK_FALLBACK` is defined in `source/AlertEngine.mc` and defaults to `false` for real BLE validation. Simulator/dev demo can set it to `true` to restore the rotating mock carousel.

The ALERT screen shows a tiny source label:

- `BLE SCAN`
- `BLE FOUND`
- `BLE CONN`
- `BLE SVC`
- `BLE CHAR`
- `BLE SUB`
- `BLE RX`
- `BLE ERR`
- `MOCK`

These diagnostic BLE labels are temporary for real Enduro 2 validation. They show the current BLE pipeline stage in the same position where `NO BLE` previously appeared.

The bottom of the HUD also shows a simplified BLE status string:

- `BLE OFF`: BLE source is stopped or not initialized
- `SCAN`: scanning has started
- `FOUND`: `SKYSHIELD-BRIDGE` was discovered
- `CONNECT`: pairing/connection or service/characteristic discovery is underway
- `SUBSCRIBE`: CCCD notification enable was requested or completed
- `RX`: at least one valid notification packet was received and parsed
- `ERROR`: BLE exception, disconnect, missing service/characteristic/descriptor, decode failure, or parse failure

## BLE Test Plan

Simulator-oriented test:

1. Build and run the Garmin app in the Connect IQ simulator.
2. Confirm the app still displays rotating mock alerts.
3. Check simulator logs for:

```text
SKYSHIELD BLE: scan started for SKYSHIELD-BRIDGE
```

With `USE_MOCK_FALLBACK = false`, the simulator should show a BLE diagnostic state such as `BLE SCAN` plus `SCAN` unless a real BLE packet is received. BLE scanning and peripheral connection usually require real hardware; simulator behavior depends on the installed Connect IQ SDK and simulator BLE support. Set `USE_MOCK_FALLBACK = true` only for simulator/demo UI work.

Real watch and ESP32 test:

1. Flash the ESP32 bridge firmware.
2. Confirm the ESP32 advertises as `SKYSHIELD-BRIDGE`.
3. Install/run the Garmin app on Enduro 2 or fenix7.
4. Watch Garmin logs for:

```text
SKYSHIELD BLE: scan started for SKYSHIELD-BRIDGE
SKYSHIELD BLE: BLE found peripheral name=<name-or-none>
SKYSHIELD BLE: BLE advertised services 9f4d0001-7c31-4f9b-9a4b-8f4c0f000001
SKYSHIELD BLE: BLE matched SKYSHIELD service
SKYSHIELD BLE: BLE connecting
SKYSHIELD BLE: connected
SKYSHIELD BLE: service discovered
SKYSHIELD BLE: characteristic discovered
SKYSHIELD BLE: subscribe requested
SKYSHIELD BLE: BLE subscribed
SKYSHIELD BLE: BLE RX packet
SKYSHIELD BLE: packet received: {...}
SKYSHIELD BLE: parser success
```

5. With ESP32 unplugged or out of range, verify the HUD shows `BLE SCAN` and `SCAN`.
6. With ESP32 advertising and sending notifications, verify the HUD advances through `BLE FOUND`, `BLE CONN`, `BLE SVC`, `BLE CHAR`, `BLE SUB`, then `BLE RX`.
7. When `BLE RX` is shown, alert fields should update from received ESP32 JSON.

Troubleshooting:

- If the watch never finds the bridge, confirm the ESP32 serial log says `BLE advertising as SKYSHIELD-BRIDGE` and the scanner logs include service UUID `9f4d0001-7c31-4f9b-9a4b-8f4c0f000001`.
- If the watch connects but receives no packets, confirm notifications are enabled on characteristic `9f4d0002-7c31-4f9b-9a4b-8f4c0f000001`.
- If parsing fails, compare the ESP32 Serial JSON with `protocol/skyshield-alert.schema.json`.
- If BLE remains at `BLE SCAN` for more than 20 seconds, the app logs `scan timeout` and continues scanning.
- If BLE reaches `BLE SUB` but no packet arrives within 20 seconds, the app logs `notification timeout after subscribe` and keeps showing `BLE SUB`.
- If BLE errors before notifications, the HUD shows `BLE ERR`.
- If BLE disconnects, `BleAlertSource` enters `SIGNAL_LOST` and restarts scanning. With `USE_MOCK_FALLBACK = false`, the HUD should return to `BLE SCAN` and `SCAN`.

## Simulated BLE Lifecycle

The simulated connection state still runs internally for the HUD prototype, but real BLE state is also exposed from `AlertEngine.getBleState()`. The top metadata label is not rendered on the ALERT screen. The HUD prioritizes RF activity, signal strength, confidence, and action state over connection plumbing.

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
- BLE validation is implemented; real watch testing is required.
- Alert JSON schema validation is not implemented on the watch.
- Vibration behavior must be validated on Garmin hardware or simulator support.
- Settings are in-memory defaults only and are not user-editable yet.
- No sound behavior exists. `silentMode` is reserved for future sound-related logic.
- RSSI-like signal strength is not precise physical distance.
- Direction fields are parsed for future compatibility but are not displayed on the Garmin HUD until real direction-finding hardware is validated.
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
