# SKYSHIELD Payload Specification

## Version

Current BLE payload version:

S2

## Format

S2|RF_TYPE|SEVERITY|BAND|STRENGTH|DRONE_CLASS

## Example Payloads

S2|F|H|58|N|FPV
S2|D|M|24|M|MAVIC
S2|U|C|X|N|UNKNOWN
S2|D|M|24|M|AUTEL

## Field Definitions

### RF_TYPE

F = FPV RF
D = DJI RF
U = UNKNOWN RF

### SEVERITY

L = LOW
M = MEDIUM
H = HIGH
C = ELEVATED

### BAND

12 = 1.2GHz
24 = 2.4GHz
33 = 3.3GHz
58 = 5.8GHz
X = MULTI RF

### STRENGTH

F = WEAK
M = MODERATE
N = STRONG

### DRONE_CLASS

FPV
MAVIC
AUTEL
UNKNOWN

## Architecture

Drone detector:
- RF detection
- vendor/protocol identification
- drone classification

Middleware:
- normalization
- filtering
- payload generation
- BLE transmission

Garmin app:
- payload parsing
- tactical HUD rendering
- haptics
- deterministic alert cycle

## Notes

Confidence percentage intentionally removed.

Garmin app must not invent:
- confidence
- triangulation
- radar sectors
- drone classification
