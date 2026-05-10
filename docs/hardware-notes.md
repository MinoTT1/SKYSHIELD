# Hardware Notes

## Garmin Enduro 2

The Garmin Enduro 2 is used as the wearable UI and vibration alert device.

Responsibilities:

- Connect to the ESP32-S3 bridge over BLE
- Receive normalized SKYSHIELD alerts
- Display concise warning information
- Trigger haptic vibration patterns

Non-responsibilities:

- RF detection
- Drone classification
- Direction finding
- Detector hardware control

## ESP32-S3

The ESP32-S3 is the middleware bridge, BLE server, and alert processor.

Responsibilities:

- Receive or simulate detector alerts
- Normalize alerts into the SKYSHIELD protocol
- Apply simple prioritization and expiry rules
- Serve alert data over BLE
- Maintain current alert state for watch reconnects

## Sensor Layer

Existing drone detectors are the sensor layer. They may provide alerts through serial, network, GPIO, BLE, Wi-Fi, or proprietary interfaces in future versions.

Future compatibility targets:

- Chuyka
- Tsukorok
- SkyDroid
- Custom RF detectors

## MVP Hardware Setup

The first MVP can be developed with:

- Garmin Enduro 2
- ESP32-S3 development board
- Simulated alert source
- Development machine for generating mock alerts

No real drone detector hardware is required for the initial MVP.

## Future Hardware Questions

- Which detector interfaces should be prioritized first?
- How should the bridge be powered in the field?
- Should the bridge include physical buttons or LEDs?
- What enclosure and ruggedization level is required?
- What is the acceptable BLE range in tactical field conditions?
