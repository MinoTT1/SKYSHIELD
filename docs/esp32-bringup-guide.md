# ESP32-S3 Bring-Up Guide

This guide covers the first hardware bring-up for the SKYSHIELD ESP32-S3 bridge.

The goal is simple: confirm the board powers on, appears as a serial device on macOS, accepts firmware upload from PlatformIO, and prints simulated SKYSHIELD alert packets over Serial.

No RF detector hardware is required for this step.

## Required Items

- ESP32-S3 development board
- USB-C data cable
- MacBook
- VSCode
- PlatformIO extension for VSCode
- Garmin simulator, optional

Use a known data-capable USB-C cable. Many charging cables will power the board but will not expose a serial port.

## First Connection Steps

1. Plug the ESP32-S3 board into the MacBook using USB-C.
2. Wait a few seconds for macOS to detect the USB serial device.
3. Open Terminal.
4. Check available serial ports:

```sh
ls /dev/cu.*
ls /dev/tty.*
```

Typical ESP32-S3 ports may look similar to:

```text
/dev/cu.usbmodemXXXX
/dev/cu.usbserial-XXXX
```

Prefer `/dev/cu.*` ports for PlatformIO upload and serial monitor on macOS.

## PlatformIO Setup

1. Open VSCode.
2. Install the PlatformIO extension if it is not already installed.
3. Open the project folder:

```text
SKYSHIELD/esp32-bridge
```

4. Build the firmware:

```sh
pio run
```

5. Upload the firmware:

```sh
pio run -t upload
```

If PlatformIO does not pick the correct port automatically, specify it:

```sh
pio run -t upload --upload-port /dev/cu.usbmodemXXXX
```

6. Open the serial monitor:

```sh
pio device monitor -b 115200
```

If needed, specify the port:

```sh
pio device monitor -p /dev/cu.usbmodemXXXX -b 115200
```

## Expected Serial Output

On boot, the ESP32-S3 should print:

```text
SKYSHIELD ESP32 Bridge starting...
```

Then it should print one canonical SKYSHIELD JSON alert approximately every 4 seconds:

```json
{"threat":"FPV","severity":"HIGH","band":"5.8GHz","distance":"NEAR","confidence":87,"bands":{"band_1_2":"LOW","band_2_4":"LOW","band_3_3":"MED","band_5_8":"HIGH"},"source":"ESP32_SIM","sequence":1}
```

The exact sequence number will increase as alerts rotate.

## Troubleshooting

### No Port Visible

- Try a different USB-C cable.
- Try a different USB port or hub.
- Unplug and reconnect the board.
- Confirm the cable supports data, not only charging.
- Check both:

```sh
ls /dev/cu.*
ls /dev/tty.*
```

### Wrong Cable

If the board powers on but no serial port appears, the cable is likely charge-only. Replace it with a known USB-C data cable.

### Permission Issue

On macOS, permission problems are less common than on Linux, but PlatformIO may still fail if another process is using the port.

- Close other serial monitors.
- Close Arduino IDE or other tools using the same port.
- Unplug and reconnect the board.

### Upload Fails

- Confirm the correct board is selected in `platformio.ini`.
- Confirm the upload port is correct.
- Try specifying the upload port manually.
- Lower upload speed later if needed.
- Put the board into bootloader mode if automatic upload does not work.

### Board Not In Bootloader Mode

Many ESP32-S3 boards support automatic bootloader entry. If upload fails:

1. Hold the `BOOT` button.
2. Tap `RESET` or reconnect USB.
3. Release `BOOT`.
4. Run upload again.

Button names vary by board. Some boards label these as `BOOT`, `0`, `RST`, or `EN`.

### Serial Monitor Blank

- Confirm baud rate is `115200`.
- Press the board reset button while the monitor is open.
- Confirm upload completed successfully.
- Confirm the monitor is connected to the same port used for upload.
- Close and reopen the serial monitor.

## Next Step After Bring-Up

After serial bring-up works, the next firmware milestone is BLE GATT:

- Enable a BLE GATT server on the ESP32-S3.
- Advertise as `SKYSHIELD-BRIDGE`.
- Expose the SKYSHIELD alert notify characteristic.
- Send one compact canonical JSON alert per BLE notification.
- Continue printing the same JSON over Serial for debugging.

The Garmin app will later subscribe to the alert characteristic, receive the UTF-8 JSON payload, pass it into `AlertParser`, and update the tactical HUD.
