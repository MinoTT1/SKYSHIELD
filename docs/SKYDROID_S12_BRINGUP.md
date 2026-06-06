# Skydroid S12 Bring-Up

## Purpose

This guide defines the first hardware bring-up plan for the Skydroid S12. The objective is to capture real detector output before implementing or changing any parser behavior.

## Bring-Up Procedure

1. Connect the Skydroid S12 to a Mac or Windows computer using a USB-C data cable.

2. Identify the serial port.

   macOS:

   ```sh
   ls /dev/tty.*
   ```

   Windows:

   Open **Device Manager**, then inspect **COM ports**.

3. Test serial output using likely serial settings.

   Primary setting:

   - `115200` baud
   - `8` data bits
   - no parity
   - `1` stop bit

   Alternative baud rates to test:

   - `9600`
   - `57600`
   - `230400`

4. Capture raw output before any drone detection activity. This establishes the idle baseline.

5. Activate a known drone or RF source in a controlled environment.

6. Capture raw output while the S12 reports detection activity.

7. Classify the observed output type:

   - ASCII text
   - CSV-like
   - JSON-like
   - binary/hex
   - no output

8. Save the unmodified captures:

   ```text
   captures/skydroid_s12_idle_001.txt
   captures/skydroid_s12_alert_001.txt
   ```

9. Map confirmed raw output fields into `SkyShieldEvent`.

10. Map the validated `SkyShieldEvent` into the existing S2 payload.

## Expected Fields

Capture and validate these fields when available:

- drone type or classification
- frequency band or frequency in MHz
- signal strength
- detection time

## Data Integrity Rule

Do not invent missing fields. Unknown or unavailable detector data must remain explicitly unknown until validated from real hardware output.
