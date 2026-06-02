#pragma once

#include <Arduino.h>

// Future-facing detector event shape for TTSKW07 integration.
// This is intentionally not wired into NormalizedAlert or BLE payload generation yet.
struct SkyShieldEvent {
    const char* rfType;
    const char* severity;
    const char* band;
    const char* strength;
    const char* droneClass;
    const char* detectorSource;
    const char* sourceDetector;
    String rawPayload;
    int rssiDbm;
    uint32_t timestampMs;
};
