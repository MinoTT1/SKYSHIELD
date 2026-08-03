#pragma once

// Parser for Tatusky TTSKW07 ASCII detection lines.
//
// Arduino-free by design so the contract test exercises this exact code
// natively against the captured samples in test_samples/.
//
// Vendor-confirmed transport (docs/TTSKW07_INTEGRATION_PLAN.md):
//   USB Virtual COM, 115200 8N1, no flow control, ASCII, realtime output.
//
// Observed line format (esp32-bridge/test_samples/ttskw07_raw_samples.txt):
//   TTSKW07 TIME=00:00:01 TYPE=DJI_MAVIC BAND=2.4GHz FREQ_MHZ=2437 RSSI=-61DBM SIGNAL=MID
//
// Keys are parsed by name, not by position, and unrecognized keys are ignored,
// so a firmware revision that adds or reorders fields does not break parsing.
//
// ---------------------------------------------------------------------------
// WHAT THIS PARSER DELIBERATELY DOES NOT DO
// ---------------------------------------------------------------------------
// The integration plan states: "Do not fake severity. Do not fake confidence.
// Missing fields must remain unknown rather than inferred without evidence."
// The TTSKW07 reports neither severity nor confidence, so:
//
//   * confidence is always ABSENT (CBOR null). The HUD renders "CONF --".
//     It is never set to 0, which would read as "certainly not a threat".
//
//   * severity is a documented SKYSHIELD MIDDLEWARE POLICY derived from the
//     detector's own SIGNAL field, not a detector claim. The mapping is
//     deterministic and is stated in docs/TTSKW07_MAPPING.md. It never yields
//     CRITICAL: nothing in TTSKW07 output justifies the top severity, and
//     escalation is the watch's job once a track is repeated and locked.
//
//   * an unclassifiable TYPE does NOT raise severity. Escalating on ignorance
//     produces exactly the false positives this product cannot afford.
//
//   * vendor identity is never invented. AUTEL_* maps to threat UNKNOWN
//     because the threat enum has no Autel value; the real vendor string is
//     preserved in drone_class instead of being misattributed to DJI.

#include "SkyShieldProtocol.h"

namespace skyshield {

static const char TTSKW07_LINE_PREFIX[] = "TTSKW07";
static const size_t TTSKW07_MAX_LINE = 200;

enum TTSKW07ParseResult : uint8_t {
    TTSKW07_OK = 0,
    TTSKW07_NOT_A_DETECTION = 1,  // noise, banner, blank: skip quietly
    TTSKW07_MALFORMED = 2         // looks like ours but is not usable
};

inline const char* ttskw07ResultName(TTSKW07ParseResult result) {
    switch (result) {
        case TTSKW07_OK: return "OK";
        case TTSKW07_NOT_A_DETECTION: return "NOT_A_DETECTION";
        default: return "MALFORMED";
    }
}

// Diagnostics preserved from the raw line but not carried on the wire. The
// schema has no RSSI field; these exist so the source data can be logged
// faithfully rather than discarded at parse time.
struct TTSKW07Diagnostics {
    bool hasRssi;
    int rssiDbm;
    bool hasFrequency;
    uint32_t frequencyMhz;
    char detectionTime[16];
    char rawType[DRONE_CLASS_CAPACITY];
};

inline void ttskw07DiagnosticsInit(TTSKW07Diagnostics& diagnostics) {
    diagnostics.hasRssi = false;
    diagnostics.rssiDbm = 0;
    diagnostics.hasFrequency = false;
    diagnostics.frequencyMhz = 0;
    diagnostics.detectionTime[0] = '\0';
    diagnostics.rawType[0] = '\0';
}

namespace detail {

inline bool isSpace(char ch) {
    return (ch == ' ') || (ch == '\t');
}

inline size_t cstrLength(const char* text) {
    size_t length = 0;

    while ((text != nullptr) && (text[length] != '\0')) {
        length += 1;
    }

    return length;
}

// Case-sensitive comparison of a bounded token against a C string. Detector
// keys are fixed-case in the vendor output, so exact matching is correct and
// avoids accepting near-miss garbage.
inline bool tokenEquals(const char* token, size_t tokenLength, const char* expected) {
    size_t i = 0;

    for (; i < tokenLength; i += 1) {
        if ((expected[i] == '\0') || (token[i] != expected[i])) {
            return false;
        }
    }

    return expected[i] == '\0';
}

inline bool tokenStartsWith(const char* token, size_t tokenLength, const char* prefix) {
    size_t i = 0;

    while (prefix[i] != '\0') {
        if ((i >= tokenLength) || (token[i] != prefix[i])) {
            return false;
        }

        i += 1;
    }

    return true;
}

inline bool copyToken(const char* token, size_t tokenLength, char* out, size_t capacity) {
    if (tokenLength >= capacity) {
        return false;
    }

    for (size_t i = 0; i < tokenLength; i += 1) {
        out[i] = token[i];
    }

    out[tokenLength] = '\0';
    return true;
}

// Parses a signed decimal with an optional non-numeric suffix, so "-61DBM"
// yields -61. Returns false when no digits are present at all.
inline bool parseSignedPrefix(const char* token, size_t tokenLength, int& outValue) {
    size_t index = 0;
    bool negative = false;

    if ((index < tokenLength) && ((token[index] == '-') || (token[index] == '+'))) {
        negative = (token[index] == '-');
        index += 1;
    }

    int value = 0;
    bool sawDigit = false;

    while ((index < tokenLength) && (token[index] >= '0') && (token[index] <= '9')) {
        value = (value * 10) + (token[index] - '0');
        sawDigit = true;
        index += 1;
    }

    if (!sawDigit) {
        return false;
    }

    outValue = negative ? -value : value;
    return true;
}

inline bool parseUnsigned(const char* token, size_t tokenLength, uint32_t& outValue) {
    uint32_t value = 0;
    bool sawDigit = false;

    for (size_t i = 0; i < tokenLength; i += 1) {
        if ((token[i] < '0') || (token[i] > '9')) {
            return false;
        }

        value = (value * 10) + static_cast<uint32_t>(token[i] - '0');
        sawDigit = true;
    }

    if (!sawDigit) {
        return false;
    }

    outValue = value;
    return true;
}

inline Band bandFromToken(const char* token, size_t length) {
    if (tokenEquals(token, length, "1.2GHz")) { return BAND_1_2; }
    if (tokenEquals(token, length, "2.4GHz")) { return BAND_2_4; }
    if (tokenEquals(token, length, "3.3GHz")) { return BAND_3_3; }
    if (tokenEquals(token, length, "5.8GHz")) { return BAND_5_8; }
    if (tokenEquals(token, length, "MULTI")) { return BAND_MULTI; }
    return BAND_UNKNOWN;
}

inline Distance distanceFromToken(const char* token, size_t length) {
    if (tokenEquals(token, length, "NEAR")) { return DISTANCE_NEAR; }
    if (tokenEquals(token, length, "MID")) { return DISTANCE_MID; }
    if (tokenEquals(token, length, "FAR")) { return DISTANCE_FAR; }
    return DISTANCE_UNKNOWN;
}

// Vendor family from the detector's TYPE token.
//
// AUTEL deliberately maps to UNKNOWN: the threat enum has no Autel value and
// labeling an Autel airframe "DJI" would be a false vendor attribution. The
// true vendor string survives in drone_class.
inline Threat threatFromTypeToken(const char* token, size_t length) {
    if (tokenStartsWith(token, length, "DJI")) { return THREAT_DJI; }
    if (tokenStartsWith(token, length, "FPV")) { return THREAT_FPV; }
    return THREAT_UNKNOWN;
}

// SKYSHIELD middleware policy, NOT a detector claim. See the header comment.
// Never returns CRITICAL.
inline Severity severityFromSignal(Distance distance) {
    switch (distance) {
        case DISTANCE_NEAR: return SEVERITY_HIGH;
        case DISTANCE_MID: return SEVERITY_MEDIUM;
        default: return SEVERITY_LOW;
    }
}

}  // namespace detail

// Parses one raw TTSKW07 line into a normalized alert.
//
// timestampMs and sequence are supplied by the caller; the parser does not
// read a clock so it stays testable and side-effect free.
inline TTSKW07ParseResult ttskw07ParseLine(const char* line,
                                           uint32_t timestampMs,
                                           uint32_t sequence,
                                           Alert& alert,
                                           TTSKW07Diagnostics& diagnostics) {
    alertInit(alert);
    ttskw07DiagnosticsInit(diagnostics);

    if (line == nullptr) {
        return TTSKW07_NOT_A_DETECTION;
    }

    const size_t lineLength = detail::cstrLength(line);

    if ((lineLength == 0) || (lineLength > TTSKW07_MAX_LINE)) {
        return TTSKW07_NOT_A_DETECTION;
    }

    size_t index = 0;

    while ((index < lineLength) && detail::isSpace(line[index])) {
        index += 1;
    }

    // Anything not carrying the detector prefix is another device's chatter, a
    // boot banner, or UART noise. Skip quietly rather than logging an error
    // per line, which would flood the console on a noisy link.
    if (!detail::tokenStartsWith(&line[index], lineLength - index, TTSKW07_LINE_PREFIX)) {
        return TTSKW07_NOT_A_DETECTION;
    }

    index += detail::cstrLength(TTSKW07_LINE_PREFIX);

    // The prefix must be a whole token: "TTSKW07X ..." is not ours.
    if ((index < lineLength) && !detail::isSpace(line[index])) {
        return TTSKW07_NOT_A_DETECTION;
    }

    bool sawType = false;
    bool sawBand = false;
    bool sawSignal = false;

    Threat threat = THREAT_UNKNOWN;
    Band band = BAND_UNKNOWN;
    Distance distance = DISTANCE_UNKNOWN;

    while (index < lineLength) {
        while ((index < lineLength) && detail::isSpace(line[index])) {
            index += 1;
        }

        if (index >= lineLength) {
            break;
        }

        const size_t tokenStart = index;

        while ((index < lineLength) && !detail::isSpace(line[index])) {
            index += 1;
        }

        const size_t tokenLength = index - tokenStart;
        const char* token = &line[tokenStart];

        size_t separator = 0;

        while ((separator < tokenLength) && (token[separator] != '=')) {
            separator += 1;
        }

        // A token with no '=' is not a key/value pair. Ignore it rather than
        // rejecting the whole line, so a trailing status word cannot discard
        // an otherwise valid detection.
        if (separator >= tokenLength) {
            continue;
        }

        const char* key = token;
        const size_t keyLength = separator;
        const char* value = &token[separator + 1];
        const size_t valueLength = tokenLength - separator - 1;

        if (valueLength == 0) {
            return TTSKW07_MALFORMED;
        }

        if (detail::tokenEquals(key, keyLength, "TYPE")) {
            threat = detail::threatFromTypeToken(value, valueLength);

            // Preserve the detector's own type string verbatim rather than
            // remapping it to a coarser label; the plan requires source data
            // be preserved faithfully before normalization.
            //
            // An over-long model name drops the label but KEEPS the detection:
            // the threat family, band and signal are still valid, and losing a
            // real detection over a cosmetic field would be the worse failure.
            if (detail::copyToken(value, valueLength, diagnostics.rawType, DRONE_CLASS_CAPACITY)) {
                alertSetDroneClass(alert, diagnostics.rawType);
            }

            sawType = true;
            continue;
        }

        if (detail::tokenEquals(key, keyLength, "BAND")) {
            band = detail::bandFromToken(value, valueLength);
            sawBand = true;
            continue;
        }

        if (detail::tokenEquals(key, keyLength, "SIGNAL")) {
            distance = detail::distanceFromToken(value, valueLength);
            sawSignal = true;
            continue;
        }

        if (detail::tokenEquals(key, keyLength, "RSSI")) {
            int rssi = 0;

            if (detail::parseSignedPrefix(value, valueLength, rssi)) {
                diagnostics.hasRssi = true;
                diagnostics.rssiDbm = rssi;
            }

            continue;
        }

        if (detail::tokenEquals(key, keyLength, "FREQ_MHZ")) {
            uint32_t frequency = 0;

            // "UNKNOWN" is a legitimate value here and must not fail the line.
            if (detail::parseUnsigned(value, valueLength, frequency)) {
                diagnostics.hasFrequency = true;
                diagnostics.frequencyMhz = frequency;
            }

            continue;
        }

        if (detail::tokenEquals(key, keyLength, "TIME")) {
            detail::copyToken(value, valueLength, diagnostics.detectionTime,
                              sizeof(diagnostics.detectionTime));
            continue;
        }

        // Unrecognized key from a newer firmware revision: ignore it.
    }

    // A detection line without these three carries nothing actionable.
    if (!sawType || !sawBand || !sawSignal) {
        return TTSKW07_MALFORMED;
    }

    alert.timestampMs = timestampMs;
    alert.sequence = sequence;
    alert.sensorType = SENSOR_RF;
    alert.threat = threat;
    alert.band = band;
    alert.distance = distance;
    alert.severity = detail::severityFromSignal(distance);

    // The TTSKW07 reports no confidence. Leave it absent (CBOR null) rather
    // than inventing a number.
    alert.hasConfidence = false;

    // Nothing identifiable and no band: a real detection with no usable
    // classification. That is precisely a contact alert.
    if ((threat == THREAT_UNKNOWN) && (band == BAND_UNKNOWN)) {
        alert.alertKind = KIND_CONTACT;
    } else {
        alert.alertKind = KIND_CLASSIFIED;
    }

    alertSetSource(alert, "TTSKW07");

    return TTSKW07_OK;
}

}  // namespace skyshield
