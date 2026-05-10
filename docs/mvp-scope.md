# MVP Scope

The first MVP validates the SKYSHIELD alert pipeline using simulated alerts.

## Included

- Universal SKYSHIELD alert JSON schema
- Example alerts for common tactical cases
- Mock alert scenarios for development and testing
- ESP32-S3 bridge documentation
- Garmin Enduro 2 app documentation
- BLE transport assumptions
- Vibration pattern definitions

## Excluded

- Real RF detection
- Direction finding
- Detector-specific production adapters
- Live Chuyka, Tsukorok, SkyDroid, or SkyDroid-like integrations
- Cloud services
- Team synchronization
- Mapping
- Production firmware
- Garmin Connect IQ production app code

## MVP Alert Model

Each alert describes a single normalized drone threat event.

Required MVP fields:

- `alert_id`
- `timestamp`
- `source`
- `threat_type`
- `risk_level`
- `confidence`
- `band`
- `distance_category`
- `vibration_pattern`

Optional MVP fields:

- `display_message`
- `recommended_action`
- `expires_in_ms`
- `metadata`

## Risk Levels

Risk levels are intentionally simple for the MVP:

- `low`: Awareness only
- `medium`: Monitor and prepare
- `high`: Immediate attention required
- `critical`: Urgent tactical warning

## Threat Types

Initial threat type values:

- `fpv`
- `dji`
- `unknown`
- `fixed_wing`
- `multirotor`

## Distance Categories

Distance is represented as a category, not a precise range:

- `unknown`
- `far`
- `medium`
- `near`

This avoids false precision when detector inputs are approximate or detector-specific.

## Success Criteria

The MVP is successful if simulated alerts can be converted into the shared protocol, transmitted over BLE assumptions, and rendered on the Garmin watch concept with correct risk text and vibration pattern mapping.
