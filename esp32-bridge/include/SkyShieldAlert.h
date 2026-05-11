#pragma once

#include <Arduino.h>

struct SkyShieldAlert {
    const char* threat;
    const char* severity;
    const char* band;
    const char* distance;
    uint8_t confidence;
};

inline String alertToJson(const SkyShieldAlert& alert) {
    String json = "{";
    json += "\"threat\":\"";
    json += alert.threat;
    json += "\",\"severity\":\"";
    json += alert.severity;
    json += "\",\"band\":\"";
    json += alert.band;
    json += "\",\"distance\":\"";
    json += alert.distance;
    json += "\",\"confidence\":";
    json += alert.confidence;
    json += "}";
    return json;
}
