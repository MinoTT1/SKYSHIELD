# ESP32 Bridge

This folder is reserved for ESP32-S3 bridge firmware documentation and future implementation.

No production firmware code is included yet.

## MVP Role

The ESP32-S3 bridge is the middleware component of SKYSHIELD.

Expected responsibilities:

- Generate simulated alerts for MVP testing
- Receive detector alerts in future versions
- Normalize incoming alerts into the SKYSHIELD protocol
- Assign or preserve risk level, confidence, band, and distance category
- Select vibration pattern hints
- Expose current alerts over BLE

## BLE Server Role

The ESP32-S3 should operate as the BLE server/peripheral. The Garmin Enduro 2 app should connect as the BLE client/central and subscribe to alert notifications.

## Future Detector Inputs

Potential detector integrations may include:

- Serial messages
- UDP or TCP messages
- GPIO event lines
- BLE or Wi-Fi detector feeds
- Vendor-specific APIs

Future compatibility targets include Chuyka, Tsukorok, SkyDroid, and custom RF detectors.

## Not In MVP

- Real RF scanning
- Direction finding
- Production detector adapters
- Mesh networking
- Encrypted transport policy
