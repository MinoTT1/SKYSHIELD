#pragma once

// Parser for the Tatusky DW01 drone detector's ASCII output.
//
// Arduino-free by design so the contract test exercises this exact code
// natively, the same arrangement as TTSKW07Parser.h.
//
// Transport (vendor-confirmed, Kawhi): BLE push, 115200 8N1, ASCII, real time.
//
// RECORD FORMAT (vendor-confirmed):
//
//   F5788R093T06C202
//    |    |   |   |
//    |    |   |   +-- C: purpose UNKNOWN, captured raw, never interpreted
//    |    |   +------ T: aircraft type code, TWO HEX DIGITS
//    |    +---------- R: signal strength, 0-128, higher = stronger
//    +--------------- F: frequency in MHz, four digits
//
// Fixed-length placeholders: no separators, no trailing description text. This
// is a different shape from the TTSKW07, which had F:/R:/T: labels, variable
// spacing and a human-readable type string at the end.
//
// Full format notes and the type table: docs/dw01-format.md
//
// ---------------------------------------------------------------------------
// THE HEX TRAP
// ---------------------------------------------------------------------------
// T is HEX. T10 is 0x10 = 16 = AUTEL EVO 2, NOT decimal 10. Reading it as
// decimal silently misclassifies every AUTEL and every FM Analog contact, and
// the result still looks like a plausible alert, so nothing downstream would
// catch it. The contract test asserts hex specifically.
//
// A second, quieter trap: 'C' is itself a valid hex digit. Reading T greedily
// would swallow the C field ("06C202" -> 0x06C202). T is therefore read as
// EXACTLY two hex characters, never greedily.
//
// ---------------------------------------------------------------------------
// WHAT THIS PARSER DELIBERATELY DOES NOT DO
// ---------------------------------------------------------------------------
//   * confidence is always ABSENT (CBOR null). The device reports none, and 0
//     would read as "certainly not a threat" rather than "no data".
//
//   * an unlisted type code degrades to threat UNKNOWN and never fails the
//     line. The raw code is preserved so a new protocol is reportable to the
//     vendor rather than lost.
//
//   * AUTEL is never reported as DJI, and WiFi-class is never reported as DJI.
//     Parrot and Tello are not DJI aircraft; that would be a false vendor
//     attribution on a threat display.
//
//   * a frequency outside every known band maps to BAND_UNKNOWN rather than
//     being force-fitted. The DW01 sweeps 0-8000MHz, so out-of-band values are
//     expected traffic, not errors.
//
//   * the C field is captured verbatim and never acted on. Its meaning is an
//     open question with the vendor; guessing would be inventing telemetry.

#include "SkyShieldProtocol.h"
#include "TTSKW07Parser.h"   // shared detail:: helpers and the band table

namespace skyshield {

static const size_t DW01_MAX_LINE = 120;
static const size_t DW01_C_FIELD_CAPACITY = 16;

// Vendor-stated bound on the R scale. Values above it are still carried; the
// flag records that the device stepped outside its own documented range.
static const uint16_t DW01_SIGNAL_MAX = 128;

enum DW01ParseResult : uint8_t {
    DW01_OK = 0,
    DW01_NOT_A_DETECTION = 1,  // noise, banner, blank: skip quietly
    DW01_MALFORMED = 2         // looked like a record but is unusable
};

inline const char* dw01ResultName(DW01ParseResult result) {
    switch (result) {
        case DW01_OK: return "OK";
        case DW01_NOT_A_DETECTION: return "NOT_A_DETECTION";
        default: return "MALFORMED";
    }
}

// R -> coarse distance. The DW01 scale is vendor-confirmed as 0-128 with higher
// meaning stronger, which is firmer than the TTSKW07 equivalent ever was, but
// the thresholds themselves are still a SKYSHIELD normalization policy and not
// a detector claim.
struct DW01SignalPolicy {
    uint16_t nearMin;
    uint16_t midMin;
};

// Scaled to the confirmed 0-128 range: NEAR from ~55%, MID from ~31%.
static const DW01SignalPolicy DW01_DEFAULT_SIGNAL_POLICY = { 70, 40 };

// INVARIANT: no entry may be SEVERITY_CRITICAL. Nothing in a single detector
// record justifies the top severity; escalation is the watch's job, based on
// track persistence the bridge does not have. The contract test enforces this.
static const TTSKW07SeverityPolicy DW01_DEFAULT_SEVERITY_POLICY = {
    SEVERITY_HIGH,    // NEAR
    SEVERITY_MEDIUM,  // MID
    SEVERITY_LOW,     // FAR
    SEVERITY_LOW      // unknown
};

// Everything the raw record carried, including the fields the wire format has
// no home for. Kept so the source data can be logged faithfully.
struct DW01Diagnostics {
    bool hasFrequency;
    uint32_t frequencyMhz;
    bool hasSignal;
    uint16_t signalValue;        // R, raw
    bool signalOutOfRange;       // R exceeded the vendor's stated 0-128
    bool hasTypeCode;
    uint16_t typeCode;           // T, already hex-decoded
    bool typeCodeRecognized;
    bool hasCField;
    // The C field verbatim. Meaning unknown; see docs/dw01-format.md.
    char cField[DW01_C_FIELD_CAPACITY];
    bool cFieldTruncated;
};

inline void dw01DiagnosticsInit(DW01Diagnostics& diagnostics) {
    diagnostics.hasFrequency = false;
    diagnostics.frequencyMhz = 0;
    diagnostics.hasSignal = false;
    diagnostics.signalValue = 0;
    diagnostics.signalOutOfRange = false;
    diagnostics.hasTypeCode = false;
    diagnostics.typeCode = 0;
    diagnostics.typeCodeRecognized = false;
    diagnostics.hasCField = false;
    diagnostics.cField[0] = '\0';
    diagnostics.cFieldTruncated = false;
}

namespace detail {

inline bool hexDigitValue(char ch, uint8_t& outValue) {
    if ((ch >= '0') && (ch <= '9')) { outValue = static_cast<uint8_t>(ch - '0'); return true; }
    if ((ch >= 'a') && (ch <= 'f')) { outValue = static_cast<uint8_t>(10 + (ch - 'a')); return true; }
    if ((ch >= 'A') && (ch <= 'F')) { outValue = static_cast<uint8_t>(10 + (ch - 'A')); return true; }
    return false;
}

// Reads EXACTLY two hex characters. Fixed width on purpose: 'C' is a valid hex
// digit, so a greedy read would consume the C field that follows.
inline bool readHexPairAt(const char* line, size_t length, size_t from,
                          uint16_t& outValue, size_t& outEnd) {
    if ((from + 2) > length) {
        return false;
    }

    uint8_t high = 0;
    uint8_t low = 0;

    if (!hexDigitValue(line[from], high) || !hexDigitValue(line[from + 1], low)) {
        return false;
    }

    outValue = static_cast<uint16_t>((high << 4) | low);
    outEnd = from + 2;
    return true;
}

// Reads an unsigned decimal of at most `maxDigits`, starting at `from`. Bounded
// so a run of digits cannot spill across into the next field.
inline bool readBoundedUnsignedAt(const char* line, size_t length, size_t from,
                                  size_t maxDigits, uint32_t& outValue, size_t& outEnd) {
    size_t i = from;
    uint32_t value = 0;
    size_t digits = 0;

    while ((i < length) && isDigit(line[i]) && (digits < maxDigits)) {
        value = (value * 10) + static_cast<uint32_t>(line[i] - '0');
        digits += 1;
        i += 1;
    }

    if (digits == 0) {
        return false;
    }

    outValue = value;
    outEnd = i;
    return true;
}

}  // namespace detail

// ---------------------------------------------------------------------------
// OFFICIAL TYPE CODE TABLE -- VENDOR CONFIRMED (Kawhi, Tatusky)
// ---------------------------------------------------------------------------
// Codes are HEX. This is the complete table as supplied; it is not inferred
// from screenshots the way the TTSKW07 table was.
//
//   0x01  DJI LB        Phantom 3A/3P/4/4A/4P, Inspire 1/2, Matrice M200
//   0x02  DJI OCU       Mavic, Mavic PRO, P4P V2.0, Mavic 2/2PRO, Air 2, Mini 3, M30
//   0x03  DJI Special   Phantom 4 RTK
//   0x04  DJI Special   MINI 2
//   0x05  DJI O3+       Mavic 3 series, AVATA
//   0x06  DJI O3        DJI FPV, Mavic Air 2S, Mini 3 Pro
//   0x07  DJI O4        DJI O4 video transmission
//   0x10  AUTEL SkyLink EVO 2
//   0x11  AUTEL SkyLink LITE/NANO
//   0x12  AUTEL SkyLink EVO 2 PRO
//   0x20  FM Analog     DIY FPV / fixed-wing aircraft models
//   0x30  WiFi          Phantom 3S, SPARK, Tello, PARROT series
//   0x00  Unrecognized
inline bool dw01IsKnownTypeCode(uint16_t typeCode) {
    switch (typeCode) {
        case 0x01: case 0x02: case 0x03: case 0x04: case 0x05: case 0x06: case 0x07:
        case 0x10: case 0x11: case 0x12:
        case 0x20:
        case 0x30:
            return true;
        default:
            // 0x00 is the device's own "Unrecognized" marker. It is a value we
            // understand, but it identifies nothing, so it is not "known".
            return false;
    }
}

// Maps a hex type code to the protocol threat enum.
//
// WiFi (0x30) currently maps to THREAT_UNKNOWN and NOT to DJI. The WiFi group
// contains Parrot and Tello, which are not DJI aircraft, so folding them into
// DJI would be a false vendor attribution on a threat display. Adding a
// first-class WiFi threat value is a protocol change awaiting a decision; see
// docs/dw01-format.md. Until then the raw code and the model text carry the
// information, and the contract test pins the no-coercion behaviour.
inline Threat dw01ThreatFromCode(uint16_t typeCode) {
    switch (typeCode) {
        case 0x01: case 0x02: case 0x03: case 0x04:
        case 0x05: case 0x06: case 0x07:
            return THREAT_DJI;
        case 0x10: case 0x11: case 0x12:
            return THREAT_AUTEL;
        case 0x20:
            return THREAT_FPV;
        case 0x30:
            return THREAT_UNKNOWN;   // WiFi class, deliberately not DJI
        default:
            return THREAT_UNKNOWN;   // 0x00 and every unlisted code
    }
}

// The model detail behind a type code.
//
// The DW01 wire format sends no description text, unlike the TTSKW07. Without
// this the operator would lose the model information entirely, so it is
// reconstructed from the vendor's table. Returns nullptr for an unlisted code:
// nothing is invented for a code we do not have.
inline const char* dw01ModelTextFromCode(uint16_t typeCode) {
    switch (typeCode) {
        case 0x01: return "DJI LB(Phantom 3A/3P/4/4A/4P, Inspire 1/2, Matrice M200)";
        // Compressed to fit DRONE_CLASS_CAPACITY (64). Every model family from
        // the vendor list is still here; the full wording is in docs/dw01-format.md.
        case 0x02: return "DJI OCU(Mavic/PRO, P4P V2.0, Mavic 2/2PRO, Air 2, Mini 3, M30)";
        case 0x03: return "DJI Special(Phantom 4 RTK)";
        case 0x04: return "DJI Special(MINI 2)";
        case 0x05: return "DJI O3+(Mavic 3 series, AVATA)";
        case 0x06: return "DJI O3(DJI FPV, Mavic Air 2S, Mini 3 Pro)";
        case 0x07: return "DJI O4(O4 video transmission)";
        case 0x10: return "AUTEL SkyLink(EVO 2)";
        case 0x11: return "AUTEL SkyLink(LITE/NANO)";
        case 0x12: return "AUTEL SkyLink(EVO 2 PRO)";
        case 0x20: return "FM Analog(DIY FPV, Aircraft model)";
        case 0x30: return "WiFi(Phantom 3S, SPARK, Tello, PARROT series)";
        case 0x00: return "Unrecognized";
        default: return nullptr;
    }
}

// Parses one raw DW01 record into a normalized alert.
//
// timestampMs and sequence are supplied by the caller; the parser reads no
// clock, so it stays testable and side-effect free.
inline DW01ParseResult dw01ParseLine(
        const char* line,
        uint32_t timestampMs,
        uint32_t sequence,
        Alert& alert,
        DW01Diagnostics& diagnostics,
        const TTSKW07SeverityPolicy& severityPolicy = DW01_DEFAULT_SEVERITY_POLICY,
        const DW01SignalPolicy& signalPolicy = DW01_DEFAULT_SIGNAL_POLICY) {
    alertInit(alert);
    dw01DiagnosticsInit(diagnostics);

    if (line == nullptr) {
        return DW01_NOT_A_DETECTION;
    }

    size_t length = detail::cstrLength(line);

    if ((length == 0) || (length > DW01_MAX_LINE)) {
        return DW01_NOT_A_DETECTION;
    }

    // Trim leading and trailing whitespace and line endings. A BLE push may
    // arrive with CR/LF or padding around the record.
    size_t begin = 0;

    while ((begin < length) &&
           (detail::isSpace(line[begin]) || (line[begin] == '\r') || (line[begin] == '\n'))) {
        begin += 1;
    }

    while ((length > begin) &&
           (detail::isSpace(line[length - 1]) || (line[length - 1] == '\r') || (line[length - 1] == '\n'))) {
        length -= 1;
    }

    if (begin >= length) {
        return DW01_NOT_A_DETECTION;
    }

    // A record starts at 'F'. Anything else is another device's chatter, a
    // banner or noise: skip quietly rather than logging an error per line.
    if (line[begin] != 'F') {
        return DW01_NOT_A_DETECTION;
    }

    uint32_t frequencyMhz = 0;
    size_t cursor = 0;

    // F: up to four digits, bounded so it cannot run into the R marker.
    if (!detail::readBoundedUnsignedAt(line, length, begin + 1, 4, frequencyMhz, cursor)) {
        return DW01_MALFORMED;
    }

    if ((cursor >= length) || (line[cursor] != 'R')) {
        return DW01_MALFORMED;
    }

    uint32_t signalValue = 0;

    // R: up to three digits, per the confirmed 0-128 range.
    if (!detail::readBoundedUnsignedAt(line, length, cursor + 1, 3, signalValue, cursor)) {
        return DW01_MALFORMED;
    }

    if ((cursor >= length) || (line[cursor] != 'T')) {
        return DW01_MALFORMED;
    }

    uint16_t typeCode = 0;

    // T: EXACTLY two hex digits. See "THE HEX TRAP" above.
    if (!detail::readHexPairAt(line, length, cursor + 1, typeCode, cursor)) {
        return DW01_MALFORMED;
    }

    diagnostics.hasFrequency = true;
    diagnostics.frequencyMhz = frequencyMhz;
    diagnostics.hasSignal = true;
    diagnostics.signalValue = static_cast<uint16_t>(signalValue);
    diagnostics.signalOutOfRange = (signalValue > DW01_SIGNAL_MAX);
    diagnostics.hasTypeCode = true;
    diagnostics.typeCode = typeCode;
    diagnostics.typeCodeRecognized = dw01IsKnownTypeCode(typeCode);

    // C: optional and never interpreted. A record without it still parses --
    // the meaning is unknown, so it cannot be a precondition for a detection.
    if ((cursor < length) && (line[cursor] == 'C')) {
        diagnostics.hasCField = true;
        diagnostics.cFieldTruncated = !detail::copyTrimmed(
            line, cursor + 1, length, diagnostics.cField, DW01_C_FIELD_CAPACITY);
    }

    alert.timestampMs = timestampMs;
    alert.sequence = sequence;
    alert.sensorType = SENSOR_RF;
    alert.threat = dw01ThreatFromCode(typeCode);

    // The raw code always travels, recognized or not. For an unlisted code it
    // is the only identifier of the new protocol, and it is what makes a field
    // report to the vendor actionable.
    //
    // NOTE: this is the HEX-DECODED value. "T11" reaches the wire as 17, where
    // the TTSKW07 parser reads the same two characters as decimal 11. See
    // docs/dw01-format.md.
    alert.hasDetectorTypeCode = true;
    alert.detectorTypeCode = typeCode;
    alert.band = detail::bandFromFrequency(frequencyMhz);
    alert.distance = (signalValue >= signalPolicy.nearMin) ? DISTANCE_NEAR
                   : (signalValue >= signalPolicy.midMin) ? DISTANCE_MID
                   : DISTANCE_FAR;
    alert.severity = detail::severityFromDistance(alert.distance, severityPolicy);

    // The device reports no confidence. Leave it absent rather than inventing
    // a number; absent is distinguishable from 0 on the wire.
    alert.hasConfidence = false;

    // Model text is reconstructed from the vendor table, because the DW01 wire
    // format carries none. An unlisted code gets no text rather than a guess.
    const char* modelText = dw01ModelTextFromCode(typeCode);

    if (modelText != nullptr) {
        alertSetDroneClass(alert, modelText);
    }

    // Nothing identifiable and no usable band: a real detection with no usable
    // classification, which is exactly a contact alert.
    if ((alert.threat == THREAT_UNKNOWN) && (alert.band == BAND_UNKNOWN)) {
        alert.alertKind = KIND_CONTACT;
    } else {
        alert.alertKind = KIND_CLASSIFIED;
    }

    alertSetSource(alert, "DW01");

    return DW01_OK;
}

}  // namespace skyshield
