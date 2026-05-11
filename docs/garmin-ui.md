# Garmin UI

The Garmin Enduro 2 is the wearable RF HUD and vibration device for SKYSHIELD.

It does not detect or classify RF sources directly. It receives normalized RF telemetry alerts from the ESP32-S3 bridge over BLE.

## UI Principles

- Show the most important RF awareness information first.
- Use short text that can be read while moving.
- Distinguish RF activity level through vibration and visual hierarchy.
- Avoid complex interactions during active alerts.
- Clear stale alerts automatically when they expire.

## Primary Alert Screen

The MVP alert screen should prioritize:

- RF action state
- RF activity level
- Classification label
- Signal-strength category
- Confidence score
- Band
- Packet freshness / BLE health metadata

Example display:

```text
HIGH
FPV RF
CONF 87%
5.8GHz
^ FRONT
STRONG
HIGH RF
```

## Vibration Patterns

Initial vibration patterns:

- `single_short`: low RF awareness cue
- `double_short`: medium RF activity
- `triple_short`: high RF activity
- `long_pulse`: elevated RF activity
- `repeat_urgent`: elevated RF activity that remains active

The exact Garmin Connect IQ haptics API behavior should be validated during implementation.

## Watch States

Recommended MVP states:

- `idle`: no active alert
- `connected`: BLE link active
- `alert_active`: RF activity visible and haptic pattern triggered
- `stale`: alert expired or bridge disconnected

## Interaction Assumptions

The MVP can keep interaction minimal:

- Start app
- Connect to ESP32-S3 bridge
- Receive RF telemetry alert
- Display active RF awareness cue
- Dismiss or wait for expiry

Historical alert browsing is future functionality.

## Limitations

- Signal strength is not physical distance.
- Classification confidence is not proof of a specific RF source.
- Direction display is experimental and optional.
- Packet freshness should be visible so operators know when data may be stale.
