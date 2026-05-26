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
    const char* droneClass;
};

inline const char* compactThreat(const char* threat);
inline const char* compactSeverity(const char* severity);
inline const char* compactBand(const char* band);
inline const char* compactDistance(const char* distance);

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

inline String alertToBleJson(const SkyShieldAlert& alert) {
    String json = "{";
    json += "\"t\":\"";
    json += compactThreat(alert.threat);
    json += "\",\"s\":\"";
    json += compactSeverity(alert.severity);
    json += "\",\"b\":\"";
    json += compactBand(alert.band);
    json += "\",\"r\":\"";
    json += compactDistance(alert.distance);
    json += "\",\"c\":";
    json += alert.confidence;
    json += "}";
    return json;
}

inline String alertToBleSimple(const SkyShieldAlert& alert) {
    String payload = "S2|";
    payload += compactThreat(alert.threat);
    payload += "|";
    payload += compactSeverity(alert.severity);
    payload += "|";
    payload += compactBand(alert.band);
    payload += "|";
    payload += compactDistance(alert.distance);
    payload += "|";
    payload += alert.droneClass;
    return payload;
}

inline const char* compactThreat(const char* threat) {
    if (strcmp(threat, "FPV") == 0) {
        return "F";
    }

    if (strcmp(threat, "DJI") == 0) {
        return "D";
    }

    return "U";
}

inline const char* compactSeverity(const char* severity) {
    if (strcmp(severity, "LOW") == 0) {
        return "L";
    }

    if (strcmp(severity, "MEDIUM") == 0) {
        return "M";
    }

    if (strcmp(severity, "HIGH") == 0) {
        return "H";
    }

    return "C";
}

inline const char* compactBand(const char* band) {
    if (strcmp(band, "1.2GHz") == 0) {
        return "12";
    }

    if (strcmp(band, "2.4GHz") == 0) {
        return "24";
    }

    if (strcmp(band, "3.3GHz") == 0) {
        return "33";
    }

    if (strcmp(band, "5.8GHz") == 0) {
        return "58";
    }

    return "X";
}

inline const char* compactDistance(const char* distance) {
    if (strcmp(distance, "FAR") == 0) {
        return "F";
    }

    if (strcmp(distance, "MID") == 0) {
        return "M";
    }

    return "N";
}
