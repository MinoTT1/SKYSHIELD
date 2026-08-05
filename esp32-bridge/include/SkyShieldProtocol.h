#pragma once

// Canonical SKYSHIELD alert model, shared by every component on the CORE side.
//
// This header is deliberately free of any Arduino dependency so the contract
// test can compile and exercise the real encoder natively. Do not add
// <Arduino.h> or String here.
//
// Semantics: protocol/skyshield-alert.schema.json
// Wire format: docs/wire-protocol.md

#include <stddef.h>
#include <stdint.h>

namespace skyshield {

// Bumped on any breaking change to field meaning or CBOR key assignment.
// Versions 1 and 2 were the retired pipe-delimited S1/S2 formats.
static const uint8_t PROTOCOL_VERSION = 3;

// Hard ceiling on an encoded packet. The encoder refuses to emit anything
// larger rather than truncating: a truncated CBOR map would decode to a
// plausible-but-wrong alert, which is the worst failure mode here.
static const size_t MAX_PAYLOAD_BYTES = 180;

// Sized to hold the TTSKW07's longest observed type description verbatim:
// "DJI OCU(Mavic, Mavic Pro, P4P V2.0, Mavic 2, Mavic 2 Pro)" is 57 bytes.
// This is a buffer capacity, not a schema constraint -- drone_class remains an
// unbounded string in protocol/skyshield-alert.schema.json. Raising it grows
// the worst-case packet to roughly 110 bytes, still well inside both
// MAX_PAYLOAD_BYTES and the 182-byte usable payload at the negotiated MTU 185.
static const size_t DRONE_CLASS_CAPACITY = 64;
static const size_t SOURCE_CAPACITY = 16;

// Enum values are wire values. They are permanent; see docs/wire-protocol.md.
// Zero always means "unknown/least" so a zero-filled or damaged packet decodes
// to something explicitly unknown rather than a confident false positive.

enum SensorType : uint8_t {
    SENSOR_RF = 0,
    SENSOR_ACOUSTIC = 1,
    SENSOR_RADAR = 2,
    SENSOR_CONTACT = 3
};

enum AlertKind : uint8_t {
    // Detector supplied usable threat/band/strength data.
    KIND_CLASSIFIED = 0,
    // Something was detected but could not be classified. A first-class
    // operational state, not a parse failure.
    KIND_CONTACT = 1
};

enum Threat : uint8_t {
    THREAT_UNKNOWN = 0,
    THREAT_FPV = 1,
    THREAT_DJI = 2
};

enum Severity : uint8_t {
    SEVERITY_LOW = 0,
    SEVERITY_MEDIUM = 1,
    SEVERITY_HIGH = 2,
    SEVERITY_CRITICAL = 3
};

enum Band : uint8_t {
    BAND_UNKNOWN = 0,
    BAND_1_2 = 1,
    BAND_2_4 = 2,
    BAND_3_3 = 3,
    BAND_5_8 = 4,
    BAND_MULTI = 5
};

// Coarse RF signal-strength category. Named "distance" for protocol
// compatibility; it is not physical range.
enum Distance : uint8_t {
    DISTANCE_UNKNOWN = 0,
    DISTANCE_FAR = 1,
    DISTANCE_MID = 2,
    DISTANCE_NEAR = 3
};

enum BandStrength : uint8_t {
    STRENGTH_NONE = 0,
    STRENGTH_LOW = 1,
    STRENGTH_MED = 2,
    STRENGTH_HIGH = 3
};

enum Direction : uint8_t {
    DIRECTION_FRONT = 0,
    DIRECTION_LEFT = 1,
    DIRECTION_RIGHT = 2,
    DIRECTION_REAR = 3
};

// CBOR map keys. Permanent: a key is never reused for a different meaning.
enum Key : uint8_t {
    KEY_PROTOCOL_VERSION = 1,
    KEY_TIMESTAMP_MS = 2,
    KEY_SEQUENCE = 3,
    KEY_SENSOR_TYPE = 4,
    KEY_ALERT_KIND = 5,
    KEY_THREAT = 6,
    KEY_SEVERITY = 7,
    KEY_BAND = 8,
    KEY_DISTANCE = 9,
    KEY_CONFIDENCE = 10,
    KEY_DRONE_CLASS = 11,
    KEY_DETECTOR_LATENCY_MS = 12,
    KEY_BANDS = 13,
    KEY_DIRECTION = 14,
    KEY_SOURCE = 15
};

// A complete normalized alert. This is the only alert struct on the CORE side;
// detectors produce it and the encoder consumes it.
struct Alert {
    uint32_t timestampMs;
    uint32_t sequence;
    SensorType sensorType;
    AlertKind alertKind;
    Threat threat;
    Severity severity;
    Band band;
    Distance distance;

    // confidence is nullable by contract: hasConfidence == false means the
    // detector reported no confidence, which is NOT the same as 0%.
    bool hasConfidence;
    uint8_t confidence;

    bool hasDroneClass;
    char droneClass[DRONE_CLASS_CAPACITY];

    bool hasDetectorLatency;
    uint32_t detectorLatencyMs;

    bool hasBands;
    BandStrength bands[4];  // [1.2, 2.4, 3.3, 5.8]

    bool hasDirection;
    Direction direction;

    bool hasSource;
    char source[SOURCE_CAPACITY];
};

// Zero-initializes to a valid, explicitly-unknown alert. Every producer should
// start from this so a forgotten field fails safe.
inline void alertInit(Alert& alert) {
    alert.timestampMs = 0;
    alert.sequence = 0;
    alert.sensorType = SENSOR_RF;
    alert.alertKind = KIND_CLASSIFIED;
    alert.threat = THREAT_UNKNOWN;
    alert.severity = SEVERITY_LOW;
    alert.band = BAND_UNKNOWN;
    alert.distance = DISTANCE_UNKNOWN;
    alert.hasConfidence = false;
    alert.confidence = 0;
    alert.hasDroneClass = false;
    alert.droneClass[0] = '\0';
    alert.hasDetectorLatency = false;
    alert.detectorLatencyMs = 0;
    alert.hasBands = false;
    alert.bands[0] = STRENGTH_NONE;
    alert.bands[1] = STRENGTH_NONE;
    alert.bands[2] = STRENGTH_NONE;
    alert.bands[3] = STRENGTH_NONE;
    alert.hasDirection = false;
    alert.direction = DIRECTION_FRONT;
    alert.hasSource = false;
    alert.source[0] = '\0';
}

// Builds a data-less contact alert: something was detected, nothing could be
// classified. Threat/band/distance stay UNKNOWN and confidence stays null.
// This is a legitimate detector output, not an error path.
inline void alertInitContact(Alert& alert, uint32_t timestampMs, uint32_t sequence) {
    alertInit(alert);
    alert.alertKind = KIND_CONTACT;
    alert.timestampMs = timestampMs;
    alert.sequence = sequence;
    alert.severity = SEVERITY_LOW;
}

// Bounded string copy into a fixed field. Returns false if the value does not
// fit, so callers can reject rather than silently store a truncated class name.
inline bool setBoundedField(char* field, size_t capacity, const char* value) {
    if ((field == nullptr) || (value == nullptr) || (capacity == 0)) {
        return false;
    }

    size_t length = 0;

    while (value[length] != '\0') {
        length += 1;

        if (length >= capacity) {
            field[0] = '\0';
            return false;
        }
    }

    for (size_t i = 0; i <= length; i += 1) {
        field[i] = value[i];
    }

    return true;
}

inline bool alertSetDroneClass(Alert& alert, const char* value) {
    if (!setBoundedField(alert.droneClass, DRONE_CLASS_CAPACITY, value)) {
        alert.hasDroneClass = false;
        return false;
    }

    alert.hasDroneClass = (alert.droneClass[0] != '\0');
    return true;
}

inline bool alertSetSource(Alert& alert, const char* value) {
    if (!setBoundedField(alert.source, SOURCE_CAPACITY, value)) {
        alert.hasSource = false;
        return false;
    }

    alert.hasSource = (alert.source[0] != '\0');
    return true;
}

// Human-readable names, used for Serial diagnostics and the contract test.
// These are the ONLY enum-to-text tables on the CORE side; the audit found
// three competing hand-written mapping tables, which is what this replaces.

inline const char* threatName(Threat value) {
    switch (value) {
        case THREAT_FPV: return "FPV";
        case THREAT_DJI: return "DJI";
        default: return "UNKNOWN";
    }
}

inline const char* severityName(Severity value) {
    switch (value) {
        case SEVERITY_MEDIUM: return "MEDIUM";
        case SEVERITY_HIGH: return "HIGH";
        case SEVERITY_CRITICAL: return "CRITICAL";
        default: return "LOW";
    }
}

inline const char* bandName(Band value) {
    switch (value) {
        case BAND_1_2: return "1.2GHz";
        case BAND_2_4: return "2.4GHz";
        case BAND_3_3: return "3.3GHz";
        case BAND_5_8: return "5.8GHz";
        case BAND_MULTI: return "MULTI";
        default: return "UNKNOWN";
    }
}

inline const char* distanceName(Distance value) {
    switch (value) {
        case DISTANCE_FAR: return "FAR";
        case DISTANCE_MID: return "MID";
        case DISTANCE_NEAR: return "NEAR";
        default: return "UNKNOWN";
    }
}

inline const char* sensorTypeName(SensorType value) {
    switch (value) {
        case SENSOR_ACOUSTIC: return "acoustic";
        case SENSOR_RADAR: return "radar";
        case SENSOR_CONTACT: return "contact";
        default: return "rf";
    }
}

inline const char* alertKindName(AlertKind value) {
    return (value == KIND_CONTACT) ? "contact" : "classified";
}

inline const char* bandStrengthName(BandStrength value) {
    switch (value) {
        case STRENGTH_LOW: return "LOW";
        case STRENGTH_MED: return "MED";
        case STRENGTH_HIGH: return "HIGH";
        default: return "NONE";
    }
}

}  // namespace skyshield
