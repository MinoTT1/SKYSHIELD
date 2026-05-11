# ESP32 Bridge

This folder contains the initial ESP32-S3 firmware scaffold for the SKYSHIELD bridge.

The current firmware is an Arduino/PlatformIO-compatible simulated-alert prototype. It does not implement BLE or real RF detection yet.

## Purpose

The ESP32-S3 bridge is the middleware component of SKYSHIELD.

Expected long-term responsibilities:

- Generate simulated alerts for MVP testing
- Receive detector alerts in future versions
- Normalize incoming alerts into the SKYSHIELD protocol
- Assign or preserve risk level, confidence, band, and distance category
- Select vibration pattern hints
- Expose current alerts over BLE

## Setup Requirements

- ESP32-S3 development board
- PlatformIO
- Arduino framework for ESP32
- USB serial monitor at `115200`

For first hardware setup, use the step-by-step bring-up guide:

- [ESP32-S3 Bring-Up Guide](../docs/esp32-bringup-guide.md)

Default PlatformIO environment:

```sh
pio run -e esp32-s3-devkitc-1
pio run -e esp32-s3-devkitc-1 -t upload
pio device monitor -b 115200
```

Adjust the `board` value in `platformio.ini` if using a different ESP32-S3 board.

## Current Simulated Mode

On boot, the firmware prints:

```text
SKYSHIELD ESP32 Bridge starting...
```

Then every 4 seconds it rotates through compact JSON alerts over Serial:

```json
{"threat":"FPV","severity":"HIGH","band":"5.8GHz","distance":"NEAR","confidence":87,"bands":{"band_1_2":"LOW","band_2_4":"LOW","band_3_3":"MED","band_5_8":"HIGH"},"source":"ESP32_SIM","sequence":1}
{"threat":"DJI","severity":"MEDIUM","band":"2.4GHz","distance":"MID","confidence":72,"bands":{"band_1_2":"LOW","band_2_4":"MED","band_3_3":"MED","band_5_8":"LOW"},"source":"ESP32_SIM","sequence":2}
{"threat":"UNKNOWN","severity":"CRITICAL","band":"MULTI","distance":"NEAR","confidence":94,"bands":{"band_1_2":"HIGH","band_2_4":"MED","band_3_3":"MED","band_5_8":"HIGH"},"source":"ESP32_SIM","sequence":3}
```

This simulated mode is intended to validate packet shape and timing before BLE transport is added.

## BLE Server Role

The ESP32-S3 should operate as the BLE server/peripheral. The Garmin Enduro 2 app should connect as the BLE client/central and subscribe to alert notifications.

Next step: implement a BLE GATT server that exposes the current SKYSHIELD alert packet through a notify characteristic.

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
- BLE GATT transport in this first scaffold
- Mesh networking
- Encrypted transport policy
