#pragma once

#include <Arduino.h>

struct SkyShieldAlert {
    const char* threat;
    const char* severity;
    const char* band;
    const char* distance;
    uint8_t confidence;
    const char* band_1_2;
    const char* band_2_4;
    const char* band_3_3;
    const char* band_5_8;
};

inline String alertToJson(const SkyShieldAlert& alert, uint32_t sequence) {
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
    json += ",\"bands\":{\"band_1_2\":\"";
    json += alert.band_1_2;
    json += "\",\"band_2_4\":\"";
    json += alert.band_2_4;
    json += "\",\"band_3_3\":\"";
    json += alert.band_3_3;
    json += "\",\"band_5_8\":\"";
    json += alert.band_5_8;
    json += "\"},\"source\":\"ESP32_SIM\",\"sequence\":";
    json += sequence;
    json += "}";
    return json;
}
