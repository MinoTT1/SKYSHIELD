#pragma once

// Parser for the Tatusky TTSKW07 handheld drone detector's ASCII output.
//
// Arduino-free by design so the contract test exercises this exact code
// natively against the captured samples in test_samples/.
//
// Transport (vendor-confirmed): USB Virtual COM, 115200 8N1, no flow control.
//
// REAL line format, from the vendor's "Handheld Drone Detector Tool" live
// output and export screenshots:
//
//   <DATE TIME>   F:<freq>MHz   R:<nnn>   T:<nn>   <type description text>
//
//   06 11:25:36   F:3320MHz   R:093   T:20   FM Analog(DIY FPV, Aircraft model)
//   05-09 09:28:00 F:5773MHz  R:046   T:05   DJI O3+(Mavic 3 series, AVATA)
//   00-01-01 17:58:38 F:5930MHz R:117 T:07   Unknown
//
// Fields are located by their F:/R:/T: labels, never by column position: the
// leading timestamp varies in width (1 to 3 date components) and the spacing
// between columns is inconsistent across captures.
//
// Full format notes and the t_code table: docs/ttskw07-format.md
//
// ---------------------------------------------------------------------------
// WHAT THIS PARSER DELIBERATELY DOES NOT DO
// ---------------------------------------------------------------------------
// Per docs/TTSKW07_INTEGRATION_PLAN.md: "Do not fake severity. Do not fake
// confidence. Missing fields must remain unknown rather than inferred without
// evidence."
//
//   * confidence is always ABSENT (CBOR null). The device reports none, and 0
//     would read as "certainly not a threat" rather than "no data".
//
//   * an unrecognized t_code degrades to threat UNKNOWN. It is never guessed
//     from the description text, and it never fails the line: the raw code and
//     the full type text are preserved so no information is lost.
//
//   * AUTEL is never reported as DJI. It is a first-class threat value as of
//     protocol version 4, and the vendor text stays intact in drone_class.
//
//   * a frequency outside every known band maps to BAND_UNKNOWN rather than
//     being force-fitted to the nearest one.
//
//   * the device timestamp is captured but NEVER used for timing. Samples show
//     it unset (00-01-01) or wrong, because it depends on the operator setting
//     the device clock. SKYSHIELD times everything on its own monotonic clock.

#include "SkyShieldProtocol.h"

namespace skyshield {

static const size_t TTSKW07_MAX_LINE = 220;
static const size_t TTSKW07_TIMESTAMP_CAPACITY = 24;

enum TTSKW07ParseResult : uint8_t {
    TTSKW07_OK = 0,
    TTSKW07_NOT_A_DETECTION = 1,  // noise, banner, blank: skip quietly
    TTSKW07_MALFORMED = 2         // has the labels but they are unusable
};

inline const char* ttskw07ResultName(TTSKW07ParseResult result) {
    switch (result) {
        case TTSKW07_OK: return "OK";
        case TTSKW07_NOT_A_DETECTION: return "NOT_A_DETECTION";
        default: return "MALFORMED";
    }
}

// Maps the detector's R value to a coarse signal-strength category.
//
// PENDING VENDOR CONFIRMATION on two points: that higher R means stronger
// signal, and that the scale is relative rather than dBm. Samples range 023 to
// 117, so it is not bounded at 100. These thresholds are a SKYSHIELD
// normalization policy, not a detector claim.
struct TTSKW07SignalPolicy {
    uint16_t nearMin;  // r >= this -> NEAR
    uint16_t midMin;   // r >= this -> MID
};

static const TTSKW07SignalPolicy TTSKW07_DEFAULT_SIGNAL_POLICY = { 70, 40 };

// SKYSHIELD middleware severity policy. The detector reports no severity, but
// severity is a required wire field, so it is derived from the signal category.
//
// INVARIANT: no entry may be SEVERITY_CRITICAL. Nothing in a single detector
// line justifies the top severity; escalation is the watch's job, based on
// track persistence the bridge does not have. The contract test enforces this.
struct TTSKW07SeverityPolicy {
    Severity onNear;
    Severity onMid;
    Severity onFar;
    Severity onUnknown;
};

static const TTSKW07SeverityPolicy TTSKW07_DEFAULT_SEVERITY_POLICY = {
    SEVERITY_HIGH,    // NEAR
    SEVERITY_MEDIUM,  // MID
    SEVERITY_LOW,     // FAR
    SEVERITY_LOW      // unknown
};

inline bool ttskw07PolicyAvoidsCritical(const TTSKW07SeverityPolicy& policy) {
    return (policy.onNear != SEVERITY_CRITICAL) &&
           (policy.onMid != SEVERITY_CRITICAL) &&
           (policy.onFar != SEVERITY_CRITICAL) &&
           (policy.onUnknown != SEVERITY_CRITICAL);
}

// Everything the raw line carried, including what the wire format has no field
// for. Kept so the source data can be logged faithfully rather than discarded.
struct TTSKW07Diagnostics {
    bool hasFrequency;
    uint32_t frequencyMhz;
    bool hasSignal;
    uint16_t signalValue;   // the R value, raw
    bool hasTypeCode;
    uint16_t typeCode;      // the T value, raw
    bool typeCodeRecognized;
    // True when the description was longer than DRONE_CLASS_CAPACITY and was
    // cut. Surfaced so a shortened label is never mistaken for the whole thing.
    bool typeTextTruncated;
    char timestamp[TTSKW07_TIMESTAMP_CAPACITY];   // device clock, NOT for timing
    char typeText[DRONE_CLASS_CAPACITY];
};

inline void ttskw07DiagnosticsInit(TTSKW07Diagnostics& diagnostics) {
    diagnostics.hasFrequency = false;
    diagnostics.frequencyMhz = 0;
    diagnostics.hasSignal = false;
    diagnostics.signalValue = 0;
    diagnostics.hasTypeCode = false;
    diagnostics.typeCode = 0;
    diagnostics.typeCodeRecognized = false;
    diagnostics.typeTextTruncated = false;
    diagnostics.timestamp[0] = '\0';
    diagnostics.typeText[0] = '\0';
}

namespace detail {

inline bool isSpace(char ch) {
    return (ch == ' ') || (ch == '\t');
}

inline bool isDigit(char ch) {
    return (ch >= '0') && (ch <= '9');
}

inline size_t cstrLength(const char* text) {
    size_t length = 0;

    while ((text != nullptr) && (text[length] != '\0')) {
        length += 1;
    }

    return length;
}

// Finds `label` at or after `from`. Returns the index just past the label, or
// npos-equivalent (length) when absent.
inline size_t findLabel(const char* line, size_t length, size_t from, const char* label) {
    const size_t labelLength = cstrLength(label);

    if (labelLength == 0) {
        return length;
    }

    for (size_t i = from; (i + labelLength) <= length; i += 1) {
        size_t j = 0;

        while ((j < labelLength) && (line[i + j] == label[j])) {
            j += 1;
        }

        if (j == labelLength) {
            return i + labelLength;
        }
    }

    return length;
}

// Reads an unsigned decimal starting at `from`, skipping leading spaces.
// Leading zeros are fine ("093"). Returns false when no digit is present.
inline bool readUnsignedAt(const char* line, size_t length, size_t from,
                           uint32_t& outValue, size_t& outEnd) {
    size_t i = from;

    while ((i < length) && isSpace(line[i])) {
        i += 1;
    }

    uint32_t value = 0;
    bool sawDigit = false;

    while ((i < length) && isDigit(line[i])) {
        value = (value * 10) + static_cast<uint32_t>(line[i] - '0');
        sawDigit = true;
        i += 1;

        if (value > 1000000u) {
            return false;  // absurd, treat as malformed rather than wrapping
        }
    }

    if (!sawDigit) {
        return false;
    }

    outValue = value;
    outEnd = i;
    return true;
}

// Copies line[begin,end) with surrounding whitespace removed. Returns false if
// the text did not fit, so a truncation is reported rather than silently
// shipping a description that looks complete but is not.
inline bool copyTrimmed(const char* line, size_t begin, size_t end,
                        char* out, size_t capacity) {
    while ((begin < end) && isSpace(line[begin])) {
        begin += 1;
    }

    while ((end > begin) && isSpace(line[end - 1])) {
        end -= 1;
    }

    size_t written = 0;

    while ((begin < end) && ((written + 1) < capacity)) {
        out[written] = line[begin];
        written += 1;
        begin += 1;
    }

    out[written] = '\0';
    return begin == end;
}

// Frequency to band.
//
// Ranges are deliberately a little wider than the nominal ISM allocations so a
// real detection at a band edge is not thrown away, but they are still bounded:
// a frequency outside all of them degrades to UNKNOWN rather than snapping to
// the nearest band. The 5.8GHz window extends to 5950 because FPV raceband
// channels run past 5900 (the captured sample at 5930MHz is one).
inline Band bandFromFrequency(uint32_t megahertz) {
    if ((megahertz >= 1100u) && (megahertz <= 1350u)) { return BAND_1_2; }
    if ((megahertz >= 2350u) && (megahertz <= 2550u)) { return BAND_2_4; }
    if ((megahertz >= 3200u) && (megahertz <= 3600u)) { return BAND_3_3; }
    if ((megahertz >= 5650u) && (megahertz <= 5950u)) { return BAND_5_8; }
    return BAND_UNKNOWN;
}

inline Distance distanceFromSignal(uint32_t signalValue, const TTSKW07SignalPolicy& policy) {
    if (signalValue >= policy.nearMin) { return DISTANCE_NEAR; }
    if (signalValue >= policy.midMin) { return DISTANCE_MID; }
    return DISTANCE_FAR;
}

inline Severity severityFromDistance(Distance distance, const TTSKW07SeverityPolicy& policy) {
    switch (distance) {
        case DISTANCE_NEAR: return policy.onNear;
        case DISTANCE_MID: return policy.onMid;
        case DISTANCE_FAR: return policy.onFar;
        default: return policy.onUnknown;
    }
}

}  // namespace detail

// Classification by the numeric T code.
//
// The code is the PRIMARY signal because it is short, stable and not
// localizable; the description text is long and may be translated.
//
// DERIVED FROM VENDOR VIDEOS AND SCREENSHOTS -- PENDING VENDOR CONFIRMATION
// VIA EMAIL. Codes not in this table are not guessed; see ttskw07ThreatFromCode.
//
//   T:20  FM Analog (DIY FPV, aircraft model)   -> FPV
//   T:06  DJI O3 (FPV, Mavic Air 2s, Mini 3)    -> DJI
//   T:05  DJI O3+ (Mavic 3 series, AVATA)       -> DJI
//   T:02  DJI OCU (Mavic, P4P V2.0, Mavic 2)    -> DJI
//   T:11  SkyLink (AUTEL Lite/Nano)             -> AUTEL
//   T:12  SkyLink (AUTEL EVO2 Pro)              -> AUTEL
//   T:07  Unknown                               -> UNKNOWN
inline bool ttskw07IsKnownTypeCode(uint16_t typeCode) {
    switch (typeCode) {
        case 2: case 5: case 6: case 7: case 11: case 12: case 20:
            return true;
        default:
            return false;
    }
}

// Maps a T code to a threat enum value.
//
// Autel is first-class as of protocol version 4. It must NEVER coerce to DJI:
// that would be a false vendor attribution on a threat display. The full vendor
// string still travels verbatim in drone_class alongside it.
inline Threat ttskw07ThreatFromCode(uint16_t typeCode) {
    switch (typeCode) {
        case 20:                    // FM Analog / analog FPV
            return THREAT_FPV;
        case 2: case 5: case 6:     // DJI OCU, O3+, O3
            return THREAT_DJI;
        case 11: case 12:           // AUTEL SkyLink Lite/Nano, EVO2 Pro
            return THREAT_AUTEL;
        default:                    // T:07 Unknown, and any unrecognized code
            return THREAT_UNKNOWN;
    }
}

// Parses one raw TTSKW07 line into a normalized alert.
//
// timestampMs and sequence are supplied by the caller; the parser reads no
// clock, so it stays testable and side-effect free.
inline TTSKW07ParseResult ttskw07ParseLine(
        const char* line,
        uint32_t timestampMs,
        uint32_t sequence,
        Alert& alert,
        TTSKW07Diagnostics& diagnostics,
        const TTSKW07SeverityPolicy& severityPolicy = TTSKW07_DEFAULT_SEVERITY_POLICY,
        const TTSKW07SignalPolicy& signalPolicy = TTSKW07_DEFAULT_SIGNAL_POLICY) {
    alertInit(alert);
    ttskw07DiagnosticsInit(diagnostics);

    if (line == nullptr) {
        return TTSKW07_NOT_A_DETECTION;
    }

    const size_t length = detail::cstrLength(line);

    if ((length == 0) || (length > TTSKW07_MAX_LINE)) {
        return TTSKW07_NOT_A_DETECTION;
    }

    // Labels are located in order, so a stray "R:" or "T:" inside the trailing
    // description text cannot be mistaken for a field.
    const size_t afterF = detail::findLabel(line, length, 0, "F:");

    if (afterF >= length) {
        // No frequency label at all: another device's chatter, a banner, or
        // UART noise. Skip quietly rather than logging an error per line.
        return TTSKW07_NOT_A_DETECTION;
    }

    const size_t afterR = detail::findLabel(line, length, afterF, "R:");
    const size_t afterT = (afterR < length) ? detail::findLabel(line, length, afterR, "T:") : length;

    if ((afterR >= length) || (afterT >= length)) {
        // It looked like a detection line but is missing R: or T:.
        return TTSKW07_MALFORMED;
    }

    uint32_t frequencyMhz = 0;
    uint32_t signalValue = 0;
    uint32_t typeCode = 0;
    size_t frequencyEnd = 0;
    size_t signalEnd = 0;
    size_t typeCodeEnd = 0;

    if (!detail::readUnsignedAt(line, length, afterF, frequencyMhz, frequencyEnd) ||
        !detail::readUnsignedAt(line, length, afterR, signalValue, signalEnd) ||
        !detail::readUnsignedAt(line, length, afterT, typeCode, typeCodeEnd)) {
        return TTSKW07_MALFORMED;
    }

    if (typeCode > 0xFFFFu) {
        return TTSKW07_MALFORMED;
    }

    diagnostics.hasFrequency = true;
    diagnostics.frequencyMhz = frequencyMhz;
    diagnostics.hasSignal = true;
    diagnostics.signalValue = static_cast<uint16_t>(signalValue);
    diagnostics.hasTypeCode = true;
    diagnostics.typeCode = static_cast<uint16_t>(typeCode);
    diagnostics.typeCodeRecognized = ttskw07IsKnownTypeCode(diagnostics.typeCode);

    // Everything before "F:" is the device timestamp. Captured for the log
    // only: the samples show it unset (00-01-01) or plainly wrong, because it
    // depends on the operator having set the device clock.
    const size_t labelStart = (afterF >= 2) ? (afterF - 2) : 0;
    detail::copyTrimmed(line, 0, labelStart, diagnostics.timestamp, TTSKW07_TIMESTAMP_CAPACITY);

    // Free-text remainder after the T code. Preserved verbatim: it carries the
    // model detail ("AVATA", "Mavic Air 2s") that the numeric code does not.
    // Real descriptions top out at 57 bytes, so truncation should not occur;
    // if it ever does, the flag makes it visible instead of silent.
    diagnostics.typeTextTruncated = !detail::copyTrimmed(
        line, typeCodeEnd, length, diagnostics.typeText, DRONE_CLASS_CAPACITY);

    alert.timestampMs = timestampMs;
    alert.sequence = sequence;
    alert.sensorType = SENSOR_RF;
    alert.threat = ttskw07ThreatFromCode(diagnostics.typeCode);

    // The raw code always travels, recognized or not. For an unrecognized code
    // it is the only identifier of the new protocol, and it is what makes a
    // field report to the vendor actionable.
    alert.hasDetectorTypeCode = true;
    alert.detectorTypeCode = diagnostics.typeCode;
    alert.band = detail::bandFromFrequency(frequencyMhz);
    alert.distance = detail::distanceFromSignal(signalValue, signalPolicy);
    alert.severity = detail::severityFromDistance(alert.distance, severityPolicy);

    // The device reports no confidence. Leave it absent rather than inventing
    // a number; absent is distinguishable from 0 on the wire.
    alert.hasConfidence = false;

    // An over-long description drops the label but KEEPS the detection: the
    // threat family, band and signal are still valid, and losing a real
    // detection over a cosmetic field would be the worse failure.
    if (diagnostics.typeText[0] != '\0') {
        alertSetDroneClass(alert, diagnostics.typeText);
    }

    // Nothing identifiable and no usable band: a real detection with no usable
    // classification, which is exactly a contact alert.
    if ((alert.threat == THREAT_UNKNOWN) && (alert.band == BAND_UNKNOWN)) {
        alert.alertKind = KIND_CONTACT;
    } else {
        alert.alertKind = KIND_CLASSIFIED;
    }

    alertSetSource(alert, "TTSKW07");

    return TTSKW07_OK;
}

}  // namespace skyshield
