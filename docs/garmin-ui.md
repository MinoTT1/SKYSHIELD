# Garmin UI

The Garmin Enduro 2 is the wearable alert display and vibration device for SKYSHIELD.

It does not detect drones. It receives normalized alerts from the ESP32-S3 bridge over BLE.

## UI Principles

- Show the most important threat information first.
- Use short text that can be read while moving.
- Distinguish urgency through vibration and visual risk level.
- Avoid complex interactions during active alerts.
- Clear stale alerts automatically when they expire.

## Primary Alert Screen

The MVP alert screen should prioritize:

- Risk level
- Threat type
- Distance category
- Confidence score
- Band
- Short message

Example display:

```text
DRONE ALERT
HIGH / FPV
Near - 92%
Band: 5.8 GHz
Take cover / scan
```

## Vibration Patterns

Initial vibration patterns:

- `single_short`: low awareness alert
- `double_short`: medium alert
- `triple_short`: high alert
- `long_pulse`: critical alert
- `repeat_urgent`: critical alert that remains active

The exact Garmin Connect IQ haptics API behavior should be validated during implementation.

## Watch States

Recommended MVP states:

- `idle`: no active alert
- `connected`: BLE link active
- `alert_active`: alert visible and haptic pattern triggered
- `stale`: alert expired or bridge disconnected

## Interaction Assumptions

The MVP can keep interaction minimal:

- Start app
- Connect to ESP32-S3 bridge
- Receive alert
- Display active alert
- Dismiss or wait for expiry

Historical alert browsing is future functionality.
