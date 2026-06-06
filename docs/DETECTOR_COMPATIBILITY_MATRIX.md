# Detector Compatibility Matrix

| Detector | Status | Interface Confidence | Data Confidence | Integration Risk | Notes |
|---|---|---:|---:|---|---|
| TTSKW07 | vendor-confirmed candidate | high | high | low-medium | USB VCP, 115200 8N1, ASCII, realtime output confirmed by vendor |
| Skydroid S12 | hardware incoming | medium-high | unknown | medium | Adapter skeleton ready; bring-up pending real serial capture |
| Skydroid S10 | potential secondary candidate | medium | medium | medium | COM/upgrade interface indicated in manual; protocol documentation unavailable |
| Chuyka 3.0 | future advanced detector candidate | unknown | unknown | high | Strong battlefield detection reputation; external data interface unknown |

## Interpretation

Interface confidence describes confidence in establishing a physical or serial connection. Data confidence describes confidence in receiving usable real-time detection fields. Integration risk combines transport uncertainty, undocumented formats, and expected normalization effort.
