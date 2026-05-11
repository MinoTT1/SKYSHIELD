# MVP Scope

The first MVP validates the SKYSHIELD wearable RF awareness pipeline using simulated RF telemetry alerts.

## Included

- Universal SKYSHIELD alert JSON schema
- Example alerts for common RF activity cases
- Mock alert scenarios for development and testing
- ESP32-S3 bridge documentation
- Garmin Enduro 2 app documentation
- BLE transport assumptions
- Vibration pattern definitions

## Excluded

- Real RF detection or raw spectrum processing
- Validated direction finding
- Detector-specific production adapters
- Live Chuyka, Tsukorok, SkyDroid, or SkyDroid-like integrations
- Cloud services
- Team synchronization
- Mapping
- Production firmware
- Garmin Connect IQ production app code

## MVP Alert Model

Each alert describes a single normalized RF activity event.

Required MVP fields:

- `alert_id`
- `timestamp`
- `source`
- `threat_type` or RF classification label
- `risk_level` or RF activity level
- `confidence`
- `band`
- `distance_category` as a protocol field, displayed as RF signal-strength category in the Garmin UI
- `vibration_pattern`

Optional MVP fields:

- `display_message`
- `recommended_action`
- `expires_in_ms`
- `metadata`

## RF Activity Levels

Protocol severity values are intentionally simple for the MVP, but UI copy should avoid overstating certainty:

- `low`: Low RF awareness cue
- `medium`: Monitor RF activity
- `high`: Elevated RF activity
- `critical`: Displayed as `ELEVATED` in the Garmin HUD until validation supports stronger language

## RF Classification Labels

Initial classification values:

- `fpv`
- `dji`
- `unknown`
- `fixed_wing`
- `multirotor`

## Signal-Strength Categories

The protocol still uses distance-like category names for compatibility, but the product should treat these as RF signal-strength categories, not physical distance:

- `unknown`
- `far`
- `medium`
- `near`

- `far`: Display as `WEAK`
- `medium`: Display as `MODERATE`
- `near`: Display as `STRONG`

This avoids false precision when RF inputs are approximate, detector-specific, or based on RSSI-like behavior.

## Success Criteria

The MVP is successful if simulated RF telemetry alerts can be converted into the shared protocol, transported over the planned BLE path, and rendered on the Garmin watch with honest RF activity labels, confidence, packet freshness, and vibration pattern mapping.

## Limitations

- RSSI is not precise distance.
- RF classification is heuristic in the MVP.
- False positives are possible.
- RF environments vary heavily by location and interference.
- Direction estimation is experimental and not included as validated MVP functionality.

## Detection Validation

Before making detection-performance claims, SKYSHIELD needs:

- Field testing
- Urban RF testing
- Open-field testing
- DJI experiments and controlled known-device trials where lawful and safe
- False positive measurement
- Latency measurement
- Battery runtime measurement

## Future KPIs

- Alert latency
- Packet freshness
- BLE stability
- False alert rate
- Battery runtime
- RF activity detection rate after real RF inputs are integrated
