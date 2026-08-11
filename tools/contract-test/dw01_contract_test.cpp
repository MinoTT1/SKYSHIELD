// SKYSHIELD DW01 contract test.
//
// Runs the REAL DW01Parser and the REAL SkyShieldCodec against the sample
// records, then asserts the full round trip: record -> parse -> encode ->
// decode -> compare.
//
// Kept in its own translation unit rather than folded into contract_test.cpp so
// that the existing, passing TTSKW07 contract test and its guardrail mutations
// are not disturbed by work for a detector nobody has plugged in yet.
//
// NOTHING HERE HAS BEEN VERIFIED AGAINST A PHYSICAL DW01. The record format and
// the type table are vendor-confirmed on paper; the samples below are the one
// real vendor example plus synthetic records built from the vendor's table.
// When the device arrives, replace dw01_raw_samples.txt with captured output
// and this test becomes a real conformance check.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "DW01Parser.h"
#include "SkyShieldCodec.h"

using namespace skyshield;

namespace {

int g_checks = 0;
int g_failures = 0;

void fail(const std::string& what, const std::string& expected, const std::string& actual) {
    std::printf("  FAIL  %s\n        expected: %s\n        actual:   %s\n",
                what.c_str(), expected.c_str(), actual.c_str());
    g_failures += 1;
}

void checkEqual(const std::string& what, const std::string& expected, const std::string& actual) {
    g_checks += 1;

    if (expected != actual) {
        fail(what, expected, actual);
    }
}

void checkTrue(const std::string& what, bool condition) {
    g_checks += 1;

    if (!condition) {
        fail(what, "true", "false");
    }
}

void checkNotEqual(const std::string& what, const std::string& forbidden, const std::string& actual) {
    g_checks += 1;

    if (forbidden == actual) {
        fail(what, "anything but " + forbidden, actual);
    }
}

// threatName/bandName/severityName/distanceName come from SkyShieldProtocol.h.
// Deliberately not redefined here: a private copy could drift from the real
// names and make a mismatch invisible.
std::string confidenceText(const Alert& alert) {
    if (!alert.hasConfidence) {
        return "null";
    }

    return std::to_string(alert.confidence);
}

std::vector<std::string> readLines(const std::string& path) {
    std::ifstream input(path.c_str());

    if (!input) {
        std::printf("cannot open %s\n", path.c_str());
        std::exit(2);
    }

    std::vector<std::string> lines;
    std::string line;

    while (std::getline(input, line)) {
        if (!line.empty() && (line[line.size() - 1] == '\r')) {
            line.erase(line.size() - 1);
        }

        lines.push_back(line);
    }

    return lines;
}

// Parses, encodes and decodes one record, and asserts the decoded alert matches
// what went in. A field that survives this survived real CBOR, not a mock.
void assertRoundTrip(const std::string& label, const Alert& parsed) {
    uint8_t buffer[MAX_PAYLOAD_BYTES];
    const size_t length = encodeAlert(parsed, buffer, sizeof(buffer));

    checkTrue(label + " encodes to a non-empty payload", length > 0);

    if (length == 0) {
        return;
    }

    Alert decoded;
    const DecodeResult status = decodeAlert(buffer, length, decoded);

    checkTrue(label + " decodes cleanly", status == DECODE_OK);

    if (status != DECODE_OK) {
        return;
    }

    checkEqual(label + " threat survives", threatName(parsed.threat), threatName(decoded.threat));
    checkEqual(label + " band survives", bandName(parsed.band), bandName(decoded.band));
    checkEqual(label + " severity survives", severityName(parsed.severity), severityName(decoded.severity));
    checkEqual(label + " distance survives", distanceName(parsed.distance), distanceName(decoded.distance));
    checkEqual(label + " confidence survives", confidenceText(parsed), confidenceText(decoded));
    checkEqual(label + " drone_class survives", std::string(parsed.droneClass), std::string(decoded.droneClass));
    checkEqual(label + " detector_type_code survives",
               std::to_string(parsed.detectorTypeCode), std::to_string(decoded.detectorTypeCode));
    checkEqual(label + " timestamp survives",
               std::to_string(parsed.timestampMs), std::to_string(decoded.timestampMs));
    checkEqual(label + " sequence survives",
               std::to_string(parsed.sequence), std::to_string(decoded.sequence));
}

// ---------------------------------------------------------------------------
// 1. The vendor's own example record
// ---------------------------------------------------------------------------
void runVendorExample() {
    std::printf("\n-- 1. vendor example F5788R093T06C202 --\n");

    Alert alert;
    DW01Diagnostics diagnostics;
    const DW01ParseResult result = dw01ParseLine("F5788R093T06C202", 1000, 1, alert, diagnostics);

    checkEqual("vendor example parses", "OK", dw01ResultName(result));
    checkEqual("F5788 -> 5788MHz", "5788", std::to_string(diagnostics.frequencyMhz));
    checkEqual("R093 -> 93", "93", std::to_string(diagnostics.signalValue));
    checkEqual("T06 -> 0x06", "6", std::to_string(diagnostics.typeCode));
    checkTrue("T06 is a listed code", diagnostics.typeCodeRecognized);
    checkEqual("0x06 -> DJI", "DJI", threatName(alert.threat));
    checkEqual("5788MHz -> 5.8GHz", "5.8GHz", bandName(alert.band));
    checkEqual("R093 -> NEAR", "NEAR", distanceName(alert.distance));
    checkEqual("confidence stays null", "null", confidenceText(alert));
    checkEqual("model text from the vendor table",
               "DJI O3(DJI FPV, Mavic Air 2S, Mini 3 Pro)", std::string(alert.droneClass));
    checkEqual("source label", "DW01", std::string(alert.source));

    // The C field is captured and never interpreted.
    checkTrue("C field captured", diagnostics.hasCField);
    checkEqual("C field verbatim", "202", std::string(diagnostics.cField));

    assertRoundTrip("vendor example", alert);
}

// ---------------------------------------------------------------------------
// 2. Hex is parsed as hex -- the trap that would silently misclassify
// ---------------------------------------------------------------------------
void runHexParsing() {
    std::printf("\n-- 2. T is hex, not decimal --\n");

    struct HexCase {
        const char* record;
        const char* text;      // what the two characters look like
        uint16_t expected;     // the hex-decoded value
        const char* threat;
    };

    // Every one of these differs between a hex and a decimal reading. If the
    // parser ever regresses to decimal, all four change threat or code.
    const HexCase cases[] = {
        { "F5788R093T10C202", "T10", 0x10, "AUTEL" },
        { "F5788R093T11C202", "T11", 0x11, "AUTEL" },
        { "F5788R093T12C202", "T12", 0x12, "AUTEL" },
        { "F3320R093T20C202", "T20", 0x20, "FPV" },
        { "F2412R064T30C130", "T30", 0x30, "UNKNOWN" }
    };

    for (size_t i = 0; i < (sizeof(cases) / sizeof(cases[0])); i += 1) {
        Alert alert;
        DW01Diagnostics diagnostics;
        const std::string tag(cases[i].text);

        checkEqual(tag + " parses", "OK",
                   dw01ResultName(dw01ParseLine(cases[i].record, 1000, 1, alert, diagnostics)));
        checkEqual(tag + " decodes as hex", std::to_string(cases[i].expected),
                   std::to_string(diagnostics.typeCode));
        checkEqual(tag + " threat", cases[i].threat, threatName(alert.threat));

        // The decimal misreading, stated explicitly so the intent is unmissable.
        const uint16_t decimalMisreading =
            static_cast<uint16_t>(((cases[i].text[1] - '0') * 10) + (cases[i].text[2] - '0'));
        checkNotEqual(tag + " is NOT read as decimal " + std::to_string(decimalMisreading),
                      std::to_string(decimalMisreading), std::to_string(diagnostics.typeCode));
    }

    // 'C' is a hex digit. A greedy hex read would swallow the C field.
    {
        Alert alert;
        DW01Diagnostics diagnostics;
        dw01ParseLine("F5788R093T06C202", 1000, 1, alert, diagnostics);
        checkEqual("T is exactly two hex chars, C not swallowed", "6",
                   std::to_string(diagnostics.typeCode));
        checkNotEqual("T did not consume C202", std::to_string(0x06C202),
                      std::to_string(diagnostics.typeCode));
    }
}

// ---------------------------------------------------------------------------
// 3. The full vendor table maps as documented
// ---------------------------------------------------------------------------
void runTypeTable() {
    std::printf("\n-- 3. complete vendor type table --\n");

    struct TableCase {
        uint16_t code;
        const char* threat;
        bool listed;
    };

    const TableCase table[] = {
        { 0x01, "DJI", true },
        { 0x02, "DJI", true },
        { 0x03, "DJI", true },
        { 0x04, "DJI", true },
        { 0x05, "DJI", true },
        { 0x06, "DJI", true },
        { 0x07, "DJI", true },
        { 0x10, "AUTEL", true },
        { 0x11, "AUTEL", true },
        { 0x12, "AUTEL", true },
        { 0x20, "FPV", true },
        { 0x30, "UNKNOWN", true },   // WiFi class, pending a protocol decision
        { 0x00, "UNKNOWN", false }   // the device's own "unrecognized"
    };

    for (size_t i = 0; i < (sizeof(table) / sizeof(table[0])); i += 1) {
        char record[32];
        std::snprintf(record, sizeof(record), "F5788R093T%02XC202", static_cast<unsigned>(table[i].code));

        Alert alert;
        DW01Diagnostics diagnostics;
        char tag[32];
        std::snprintf(tag, sizeof(tag), "0x%02X", static_cast<unsigned>(table[i].code));

        checkEqual(std::string(tag) + " parses", "OK",
                   dw01ResultName(dw01ParseLine(record, 1000, 1, alert, diagnostics)));
        checkEqual(std::string(tag) + " threat", table[i].threat, threatName(alert.threat));
        checkEqual(std::string(tag) + " raw code carried",
                   std::to_string(table[i].code), std::to_string(alert.detectorTypeCode));
        // An over-long entry is silently dropped by alertSetDroneClass, so the
        // length is asserted directly rather than inferred from emptiness.
        const char* modelText = dw01ModelTextFromCode(table[i].code);
        checkTrue(std::string(tag) + " model text fits DRONE_CLASS_CAPACITY",
                  (modelText != nullptr) && (std::strlen(modelText) < DRONE_CLASS_CAPACITY));
        checkTrue(std::string(tag) + " model text present",
                  alert.droneClass[0] != '\0');
        checkEqual(std::string(tag) + " model text survives intact",
                   std::string(modelText), std::string(alert.droneClass));
        checkEqual(std::string(tag) + " listed flag", table[i].listed ? "true" : "false",
                   diagnostics.typeCodeRecognized ? "true" : "false");

        assertRoundTrip(std::string(tag), alert);
    }
}

// ---------------------------------------------------------------------------
// 4. Negative guardrails -- the mistakes that would be invisible downstream
// ---------------------------------------------------------------------------
void runGuardrails() {
    std::printf("\n-- 4. negative guardrails --\n");

    // AUTEL must never become DJI. A false vendor attribution on a threat
    // display is worse than saying nothing.
    {
        const char* autelCodes[] = { "F5788R093T10C202", "F5788R093T11C202", "F5788R093T12C202" };

        for (size_t i = 0; i < 3; i += 1) {
            Alert alert;
            DW01Diagnostics diagnostics;
            dw01ParseLine(autelCodes[i], 1000, 1, alert, diagnostics);

            checkEqual("AUTEL stays AUTEL", "AUTEL", threatName(alert.threat));
            checkNotEqual("AUTEL never becomes DJI", "DJI", threatName(alert.threat));
            checkNotEqual("AUTEL never becomes FPV", "FPV", threatName(alert.threat));
        }
    }

    // WiFi (0x30) must not be coerced into DJI. Parrot and Tello are not DJI.
    {
        Alert alert;
        DW01Diagnostics diagnostics;
        dw01ParseLine("F2412R064T30C130", 1000, 1, alert, diagnostics);

        checkNotEqual("WiFi 0x30 is NOT coerced to DJI", "DJI", threatName(alert.threat));
        checkNotEqual("WiFi 0x30 is NOT coerced to FPV", "FPV", threatName(alert.threat));
        checkNotEqual("WiFi 0x30 is NOT coerced to AUTEL", "AUTEL", threatName(alert.threat));
        checkEqual("WiFi 0x30 degrades to UNKNOWN pending a protocol decision",
                   "UNKNOWN", threatName(alert.threat));
        checkEqual("WiFi raw code 0x30 is preserved", "48",
                   std::to_string(alert.detectorTypeCode));
        checkEqual("WiFi model text is preserved",
                   "WiFi(Phantom 3S, SPARK, Tello, PARROT series)", std::string(alert.droneClass));
    }

    // An unlisted code degrades without crashing and without guessing.
    {
        const uint16_t unlisted[] = { 0x08, 0x09, 0x13, 0x21, 0x31, 0x40, 0x99, 0xFF };

        for (size_t i = 0; i < (sizeof(unlisted) / sizeof(unlisted[0])); i += 1) {
            char record[32];
            std::snprintf(record, sizeof(record), "F5788R093T%02XC202", static_cast<unsigned>(unlisted[i]));

            Alert alert;
            DW01Diagnostics diagnostics;
            char tag[40];
            std::snprintf(tag, sizeof(tag), "unlisted 0x%02X", static_cast<unsigned>(unlisted[i]));

            checkEqual(std::string(tag) + " still parses", "OK",
                       dw01ResultName(dw01ParseLine(record, 1000, 1, alert, diagnostics)));
            checkEqual(std::string(tag) + " degrades to UNKNOWN", "UNKNOWN", threatName(alert.threat));
            checkTrue(std::string(tag) + " is flagged unlisted", !diagnostics.typeCodeRecognized);
            checkEqual(std::string(tag) + " raw code retained",
                       std::to_string(unlisted[i]), std::to_string(alert.detectorTypeCode));
            checkEqual(std::string(tag) + " no model text invented", "",
                       std::string(alert.droneClass));

            assertRoundTrip(std::string(tag), alert);
        }
    }

    // Bands are not force-fitted. The DW01 sweeps 0-8000MHz, so out-of-band
    // frequencies are ordinary traffic and must degrade, not snap to a band.
    {
        struct BandCase { const char* record; const char* band; };

        const BandCase cases[] = {
            { "F1250R093T01C202", "1.2GHz" },
            { "F2419R093T02C202", "2.4GHz" },
            { "F3320R093T20C202", "3.3GHz" },
            { "F5788R093T06C202", "5.8GHz" },
            { "F0900R093T06C202", "UNKNOWN" },   // below every band
            { "F1800R093T06C202", "UNKNOWN" },   // between 1.2 and 2.4
            { "F4000R093T06C202", "UNKNOWN" },   // between 3.3 and 5.8
            { "F7900R093T06C202", "UNKNOWN" },   // top of the DW01 sweep
            { "F0000R093T06C202", "UNKNOWN" }    // zero
        };

        for (size_t i = 0; i < (sizeof(cases) / sizeof(cases[0])); i += 1) {
            Alert alert;
            DW01Diagnostics diagnostics;
            const std::string tag(cases[i].record);

            checkEqual(tag + " parses", "OK",
                       dw01ResultName(dw01ParseLine(cases[i].record, 1000, 1, alert, diagnostics)));
            checkEqual(tag + " band", cases[i].band, bandName(alert.band));
        }
    }

    // Severity policy must never reach CRITICAL from a single record.
    {
        const uint16_t signals[] = { 0, 1, 39, 40, 69, 70, 100, 128, 200 };

        for (size_t i = 0; i < (sizeof(signals) / sizeof(signals[0])); i += 1) {
            char record[32];
            std::snprintf(record, sizeof(record), "F5788R%03uT06C202", static_cast<unsigned>(signals[i]));

            Alert alert;
            DW01Diagnostics diagnostics;
            dw01ParseLine(record, 1000, 1, alert, diagnostics);

            checkNotEqual("severity never CRITICAL from one record",
                          "CRITICAL", severityName(alert.severity));
        }

        checkTrue("the DW01 severity policy avoids CRITICAL by construction",
                  ttskw07PolicyAvoidsCritical(DW01_DEFAULT_SEVERITY_POLICY));
    }

    // Confidence is absent, never a fabricated zero.
    {
        Alert alert;
        DW01Diagnostics diagnostics;
        dw01ParseLine("F5788R093T06C202", 1000, 1, alert, diagnostics);

        checkTrue("confidence is absent", !alert.hasConfidence);
        checkNotEqual("confidence is not a fabricated 0", "0", confidenceText(alert));
    }
}

// ---------------------------------------------------------------------------
// 5. The C field, and malformed input
// ---------------------------------------------------------------------------
void runCFieldAndMalformed() {
    std::printf("\n-- 5. C field handling and malformed input --\n");

    // A missing C must NOT break the detection: its meaning is unknown, so it
    // cannot be a precondition for reporting a drone.
    {
        Alert alert;
        DW01Diagnostics diagnostics;

        checkEqual("record without C still parses", "OK",
                   dw01ResultName(dw01ParseLine("F5788R093T06", 1000, 1, alert, diagnostics)));
        checkTrue("C absent is recorded as absent", !diagnostics.hasCField);
        checkEqual("threat unaffected by a missing C", "DJI", threatName(alert.threat));
        assertRoundTrip("no C field", alert);
    }

    // An empty C is captured as empty, not treated as an error.
    {
        Alert alert;
        DW01Diagnostics diagnostics;

        checkEqual("record with empty C parses", "OK",
                   dw01ResultName(dw01ParseLine("F5788R093T06C", 1000, 1, alert, diagnostics)));
        checkTrue("empty C is still marked present", diagnostics.hasCField);
        checkEqual("empty C is empty", "", std::string(diagnostics.cField));
    }

    // An unexpected C value is captured verbatim, never validated away.
    {
        struct CCase { const char* record; const char* expected; };

        const CCase cases[] = {
            { "F5788R093T06C202", "202" },
            { "F5788R093T06C000", "000" },
            { "F5788R093T06C99999", "99999" },
            { "F5788R093T06CABC", "ABC" }
        };

        for (size_t i = 0; i < (sizeof(cases) / sizeof(cases[0])); i += 1) {
            Alert alert;
            DW01Diagnostics diagnostics;
            dw01ParseLine(cases[i].record, 1000, 1, alert, diagnostics);

            checkEqual(std::string("C captured verbatim: ") + cases[i].expected,
                       cases[i].expected, std::string(diagnostics.cField));
        }
    }

    // Noise is skipped quietly; broken records are reported, not silently
    // accepted as a detection.
    {
        struct BadCase { const char* record; const char* expected; };

        const BadCase cases[] = {
            { "", "NOT_A_DETECTION" },
            { "banner: DW01 v1.0 ready", "NOT_A_DETECTION" },
            { "   ", "NOT_A_DETECTION" },
            { "X5788R093T06C202", "NOT_A_DETECTION" },
            { "FR093T06C202", "MALFORMED" },         // no frequency digits
            { "F5788T06C202", "MALFORMED" },         // no R marker
            { "F5788R093X06C202", "MALFORMED" },     // no T marker
            { "F5788R093T0", "MALFORMED" },          // T truncated to one digit
            { "F5788R093TZZC202", "MALFORMED" }      // T not hex
        };

        for (size_t i = 0; i < (sizeof(cases) / sizeof(cases[0])); i += 1) {
            Alert alert;
            DW01Diagnostics diagnostics;
            const std::string tag = std::string("\"") + cases[i].record + "\"";

            checkEqual(tag + " -> " + cases[i].expected, cases[i].expected,
                       dw01ResultName(dw01ParseLine(cases[i].record, 1000, 1, alert, diagnostics)));
        }

        // A null pointer must not crash the parser.
        Alert alert;
        DW01Diagnostics diagnostics;
        checkEqual("null input is handled", "NOT_A_DETECTION",
                   dw01ResultName(dw01ParseLine(nullptr, 1000, 1, alert, diagnostics)));
    }

    // A GENUINE AMBIGUITY OF THE FIXED-WIDTH FORMAT, pinned so it is a known
    // property rather than a surprise: "T6C202" is indistinguishable from a
    // valid two-hex-digit code 0x6C followed by no C field. The parser takes
    // the fixed-width reading, which is the vendor's stated format, and the
    // unlisted code degrades to UNKNOWN. It does NOT guess that the operator
    // meant T06. See docs/dw01-format.md.
    {
        Alert alert;
        DW01Diagnostics diagnostics;

        checkEqual("T6C202 parses under the fixed-width rule", "OK",
                   dw01ResultName(dw01ParseLine("F5788R093T6C202", 1000, 1, alert, diagnostics)));
        checkEqual("T6C202 reads as 0x6C, not 0x06", "108",
                   std::to_string(diagnostics.typeCode));
        checkEqual("0x6C is unlisted so it degrades", "UNKNOWN", threatName(alert.threat));
        checkTrue("0x6C is flagged unlisted", !diagnostics.typeCodeRecognized);
        checkTrue("no C field found after a two-char code", !diagnostics.hasCField);
    }

    // Surrounding whitespace and line endings are tolerated: a BLE push may
    // arrive padded.
    {
        Alert alert;
        DW01Diagnostics diagnostics;

        checkEqual("padded record parses", "OK",
                   dw01ResultName(dw01ParseLine("  F5788R093T06C202  \r\n", 1000, 1, alert, diagnostics)));
        checkEqual("padded record still DJI", "DJI", threatName(alert.threat));
    }

    // R above the vendor's stated maximum is carried and flagged, not dropped.
    {
        Alert alert;
        DW01Diagnostics diagnostics;

        checkEqual("R200 still parses", "OK",
                   dw01ResultName(dw01ParseLine("F5788R200T06C202", 1000, 1, alert, diagnostics)));
        checkEqual("R200 value retained", "200", std::to_string(diagnostics.signalValue));
        checkTrue("R200 flagged as out of the stated range", diagnostics.signalOutOfRange);
        Alert atMax;
        DW01Diagnostics atMaxDiagnostics;
        dw01ParseLine("F5788R128T06C202", 1000, 1, atMax, atMaxDiagnostics);
        checkTrue("R128 is exactly at the stated maximum, not flagged",
                  !atMaxDiagnostics.signalOutOfRange);
    }
}

// ---------------------------------------------------------------------------
// 6. Every sample file record round-trips
// ---------------------------------------------------------------------------
void runSampleFile(const std::string& samplesPath) {
    std::printf("\n-- 6. sample file round trip --\n");

    const std::vector<std::string> lines = readLines(samplesPath);
    int detections = 0;

    for (size_t i = 0; i < lines.size(); i += 1) {
        if (lines[i].empty()) {
            continue;
        }

        Alert alert;
        DW01Diagnostics diagnostics;
        const DW01ParseResult result =
            dw01ParseLine(lines[i].c_str(), 1000 + static_cast<uint32_t>(i),
                          static_cast<uint32_t>(i + 1), alert, diagnostics);

        const std::string label = "sample[" + std::to_string(i) + "] " + lines[i];

        checkEqual(label + " parses", "OK", dw01ResultName(result));

        if (result != DW01_OK) {
            continue;
        }

        detections += 1;
        checkEqual(label + " confidence null", "null", confidenceText(alert));
        checkNotEqual(label + " severity not CRITICAL", "CRITICAL", severityName(alert.severity));
        assertRoundTrip(label, alert);
    }

    checkTrue("sample file produced detections", detections > 0);
    std::printf("  %d records round-tripped\n", detections);
}

}  // namespace

int main(int argc, char** argv) {
    std::printf("SKYSHIELD DW01 contract test\n");
    std::printf("NOT hardware-verified: no physical DW01 has been connected.\n");

    runVendorExample();
    runHexParsing();
    runTypeTable();
    runGuardrails();
    runCFieldAndMalformed();

    if (argc > 1) {
        runSampleFile(argv[1]);
    }

    std::printf("\n%d checks, %d failures\n", g_checks, g_failures);

    return (g_failures == 0) ? 0 : 1;
}
