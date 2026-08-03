// SKYSHIELD contract test.
//
// Runs the REAL parser, encoder and decoder natively -- not a reimplementation.
// That is why TTSKW07Parser.h and SkyShieldCodec.h are Arduino-free.
//
// Three layers:
//
//   1. ROUND TRIP: every line of ttskw07_raw_samples.txt goes
//      parse -> encode -> decode and must match expected_alerts.txt, including
//      the exact CBOR bytes. Non-detection lines must emit no alert.
//
//   2. GUARDRAIL: explicit negative assertions that fail if any of the four
//      retired misleading mappings are reintroduced. See docs/TTSKW07_MAPPING.md.
//      Proven to have teeth by tools/contract-test/verify_guardrail.sh, which
//      reintroduces each old mapping and confirms this test fails.
//
//   3. CODEC: encoder/decoder edge cases, so protocol drift cannot return
//      silently the way it did before protocol_version 3.
//
// Build and run: tools/contract-test/run.sh

#include "SkyShieldCodec.h"
#include "TTSKW07Parser.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

using namespace skyshield;

namespace {

int gChecks = 0;
int gFailures = 0;

void fail(const std::string& what, const std::string& expected, const std::string& actual) {
    gFailures += 1;
    printf("  FAIL %s\n        expected: %s\n        actual:   %s\n",
           what.c_str(), expected.c_str(), actual.c_str());
}

void checkEqual(const std::string& what, const std::string& expected, const std::string& actual) {
    gChecks += 1;

    if (expected != actual) {
        fail(what, expected, actual);
    }
}

void checkTrue(const std::string& what, bool condition) {
    gChecks += 1;

    if (!condition) {
        fail(what, "true", "false");
    }
}

// Negative assertion: the guardrail layer. Phrased as "must NOT be" so a
// reintroduced old mapping trips it directly.
void checkNotEqual(const std::string& what, const std::string& forbidden, const std::string& actual) {
    gChecks += 1;

    if (forbidden == actual) {
        gFailures += 1;
        printf("  FAIL %s\n        must NOT be: %s\n        but was:     %s\n",
               what.c_str(), forbidden.c_str(), actual.c_str());
    }
}

std::string toHex(const uint8_t* bytes, size_t length) {
    static const char* digits = "0123456789ABCDEF";
    std::string out;

    for (size_t i = 0; i < length; i += 1) {
        out += digits[(bytes[i] >> 4) & 0x0F];
        out += digits[bytes[i] & 0x0F];
    }

    return out;
}

std::string confidenceText(const Alert& alert) {
    if (!alert.hasConfidence) {
        return "null";
    }

    return std::to_string(static_cast<int>(alert.confidence));
}

std::vector<std::string> splitPipe(const std::string& line) {
    std::vector<std::string> fields;
    std::string current;
    std::istringstream stream(line);

    while (std::getline(stream, current, '|')) {
        fields.push_back(current);
    }

    return fields;
}

std::vector<std::string> readLines(const std::string& path, bool keepBlank) {
    std::vector<std::string> lines;
    std::ifstream input(path.c_str());

    if (!input) {
        printf("FATAL: cannot open %s\n", path.c_str());
        gFailures += 1;
        return lines;
    }

    std::string line;

    while (std::getline(input, line)) {
        while (!line.empty() && (line[line.size() - 1] == '\r')) {
            line.erase(line.size() - 1);
        }

        if (!keepBlank && (line.empty() || (line[0] == '#'))) {
            continue;
        }

        lines.push_back(line);
    }

    return lines;
}

// ---------------------------------------------------------------------------
// Layer 1: round trip against the fixture
// ---------------------------------------------------------------------------

void runRoundTrip(const std::string& samplesPath, const std::string& fixturePath) {
    printf("\n[1] ROUND TRIP  parse -> encode -> decode vs fixture\n");

    // Blank lines are kept: a whitespace-only line is one of the cases the
    // parser must skip, so dropping it here would hide the assertion.
    const std::vector<std::string> samples = readLines(samplesPath, true);
    const std::vector<std::string> fixture = readLines(fixturePath, false);

    if (samples.empty() || fixture.empty()) {
        return;
    }

    checkEqual("fixture row count matches sample line count",
               std::to_string(samples.size()), std::to_string(fixture.size()));

    const size_t rows = (samples.size() < fixture.size()) ? samples.size() : fixture.size();

    for (size_t i = 0; i < rows; i += 1) {
        const std::vector<std::string> expected = splitPipe(fixture[i]);

        if (expected.size() < 11) {
            fail("fixture row " + std::to_string(i) + " is malformed", "11 fields",
                 std::to_string(expected.size()) + " fields");
            continue;
        }

        const std::string label = "line " + std::to_string(i);
        const uint32_t timestampMs = 1000u + static_cast<uint32_t>(i);
        const uint32_t sequence = static_cast<uint32_t>(i) + 1u;

        Alert parsed;
        TTSKW07Diagnostics diagnostics;
        const TTSKW07ParseResult result =
            ttskw07ParseLine(samples[i].c_str(), timestampMs, sequence, parsed, diagnostics);

        if (expected[1] == "SKIPPED") {
            // A non-detection must emit NO alert at all. Asserting only on the
            // result code would let a parser that returns OK-with-empty-fields
            // slip through, so the reason is checked too.
            checkTrue(label + " emits no alert", result != TTSKW07_OK);
            checkEqual(label + " skip reason", expected[2], ttskw07ResultName(result));
            continue;
        }

        checkEqual(label + " parses", "OK", ttskw07ResultName(result));

        if (result != TTSKW07_OK) {
            continue;
        }

        uint8_t buffer[MAX_PAYLOAD_BYTES];
        const size_t length = encodeAlert(parsed, buffer, sizeof(buffer));

        checkTrue(label + " encodes", length > 0);

        if (length == 0) {
            continue;
        }

        // Locking the exact bytes means any change to key assignment, enum
        // numbering or integer encoding fails loudly instead of silently
        // shipping a format the watch cannot read.
        checkEqual(label + " CBOR bytes", expected[10], toHex(buffer, length));

        Alert decoded;
        const DecodeResult decodeStatus = decodeAlert(buffer, length, decoded);

        checkEqual(label + " decodes", "OK", decodeResultName(decodeStatus));

        if (decodeStatus != DECODE_OK) {
            continue;
        }

        checkEqual(label + " kind", expected[2], alertKindName(decoded.alertKind));
        checkEqual(label + " threat", expected[3], threatName(decoded.threat));
        checkEqual(label + " band", expected[4], bandName(decoded.band));
        checkEqual(label + " distance", expected[5], distanceName(decoded.distance));
        checkEqual(label + " severity", expected[6], severityName(decoded.severity));
        checkEqual(label + " confidence", expected[7], confidenceText(decoded));
        checkEqual(label + " drone_class", expected[8],
                   decoded.hasDroneClass ? std::string(decoded.droneClass) : std::string("-"));
        checkEqual(label + " source", expected[9],
                   decoded.hasSource ? std::string(decoded.source) : std::string("-"));

        // Survives the round trip, not just the encode.
        checkEqual(label + " sequence survives", std::to_string(sequence),
                   std::to_string(decoded.sequence));
        checkEqual(label + " timestamp survives", std::to_string(timestampMs),
                   std::to_string(decoded.timestampMs));
    }
}

// ---------------------------------------------------------------------------
// Layer 2: guardrail against the four retired mappings
// ---------------------------------------------------------------------------

// Parses one line and returns the decoded alert, so the guardrail asserts on
// what actually comes off the wire rather than on parser internals.
bool decodeSampleLine(const char* line, Alert& decoded) {
    Alert parsed;
    TTSKW07Diagnostics diagnostics;

    if (ttskw07ParseLine(line, 1000, 1, parsed, diagnostics) != TTSKW07_OK) {
        return false;
    }

    uint8_t buffer[MAX_PAYLOAD_BYTES];
    const size_t length = encodeAlert(parsed, buffer, sizeof(buffer));

    if (length == 0) {
        return false;
    }

    return decodeAlert(buffer, length, decoded) == DECODE_OK;
}

void runGuardrail() {
    printf("\n[2] GUARDRAIL  the four retired mappings must not return\n");

    const char* mavicLine =
        "TTSKW07 TIME=00:00:01 TYPE=DJI_MAVIC BAND=2.4GHz FREQ_MHZ=2437 RSSI=-61DBM SIGNAL=MID";
    const char* o3Line =
        "TTSKW07 TIME=00:00:05 TYPE=DJI_O3 BAND=5.8GHz FREQ_MHZ=5805 RSSI=-48DBM SIGNAL=NEAR";
    const char* autelLine =
        "TTSKW07 TIME=00:00:13 TYPE=AUTEL_EVO BAND=2.4GHz FREQ_MHZ=2462 RSSI=-66DBM SIGNAL=MID";
    const char* unknownLine =
        "TTSKW07 TIME=00:00:17 TYPE=UNKNOWN BAND=MULTI FREQ_MHZ=UNKNOWN RSSI=-42DBM SIGNAL=NEAR";

    Alert alert;

    // --- #1 confidence is null, never 0 -------------------------------------
    // "CONF 0%" on a threat HUD reads as "certainly not a threat" when the
    // truth is "the detector told us nothing".
    if (decodeSampleLine(mavicLine, alert)) {
        checkTrue("#1 DJI_MAVIC confidence is absent", !alert.hasConfidence);
        checkNotEqual("#1 DJI_MAVIC confidence must not be a number", "0", confidenceText(alert));
        checkEqual("#1 DJI_MAVIC confidence reads null", "null", confidenceText(alert));
    } else {
        fail("#1 DJI_MAVIC line decodes", "decoded", "failed");
    }

    if (decodeSampleLine(unknownLine, alert)) {
        checkTrue("#1 UNKNOWN confidence is absent", !alert.hasConfidence);
    }

    // --- #2 failed classification never becomes CRITICAL --------------------
    // The old fixture mapped an unclassifiable detection to CRITICAL, which is
    // escalation on ignorance.
    if (decodeSampleLine(unknownLine, alert)) {
        checkNotEqual("#2 unclassified UNKNOWN must not be CRITICAL",
                      "CRITICAL", severityName(alert.severity));
        checkEqual("#2 unclassified UNKNOWN with NEAR signal is HIGH",
                   "HIGH", severityName(alert.severity));
        checkEqual("#2 threat stays UNKNOWN", "UNKNOWN", threatName(alert.threat));
    } else {
        fail("#2 UNKNOWN line decodes", "decoded", "failed");
    }

    // The policy itself must be incapable of emitting CRITICAL, so no future
    // tuning of the table can reintroduce escalation on ignorance.
    checkTrue("#2 default severity policy can never emit CRITICAL",
              ttskw07PolicyAvoidsCritical(TTSKW07_DEFAULT_SEVERITY_POLICY));

    // No TTSKW07 line, at any signal strength, may reach CRITICAL.
    {
        const char* signals[] = { "NEAR", "MID", "FAR", "UNKNOWN", "BOGUS" };

        for (size_t i = 0; i < (sizeof(signals) / sizeof(signals[0])); i += 1) {
            std::string line = "TTSKW07 TYPE=DJI_MAVIC BAND=2.4GHz SIGNAL=";
            line += signals[i];

            if (decodeSampleLine(line.c_str(), alert)) {
                checkNotEqual(std::string("#2 SIGNAL=") + signals[i] + " must not be CRITICAL",
                              "CRITICAL", severityName(alert.severity));
            }
        }
    }

    // --- #3 Autel is never attributed to DJI --------------------------------
    if (decodeSampleLine(autelLine, alert)) {
        checkNotEqual("#3 AUTEL_EVO threat must not be DJI", "DJI", threatName(alert.threat));
        checkEqual("#3 AUTEL_EVO threat is UNKNOWN", "UNKNOWN", threatName(alert.threat));
        checkEqual("#3 AUTEL_EVO vendor survives in drone_class", "AUTEL_EVO",
                   alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
    } else {
        fail("#3 AUTEL_EVO line decodes", "decoded", "failed");
    }

    // --- #4 model names are preserved, not remapped -------------------------
    if (decodeSampleLine(o3Line, alert)) {
        checkNotEqual("#4 DJI_O3 drone_class must not be MAVIC", "MAVIC",
                      alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
        checkEqual("#4 DJI_O3 drone_class is preserved verbatim", "DJI_O3",
                   alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
        checkEqual("#4 DJI_O3 threat family is still DJI", "DJI", threatName(alert.threat));
    } else {
        fail("#4 DJI_O3 line decodes", "decoded", "failed");
    }

    if (decodeSampleLine(mavicLine, alert)) {
        checkEqual("#4 DJI_MAVIC drone_class is preserved verbatim", "DJI_MAVIC",
                   alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
    }
}

// ---------------------------------------------------------------------------
// Layer 3: codec behavior
// ---------------------------------------------------------------------------

void runCodec() {
    printf("\n[3] CODEC  encoding and validation edge cases\n");

    // A contact alert must survive the round trip with confidence still null.
    // This is the case the retired S2 format could not express at all.
    {
        Alert contact;
        alertInitContact(contact, 30110, 7);
        alertSetSource(contact, "TTSKW07");

        uint8_t buffer[MAX_PAYLOAD_BYTES];
        const size_t length = encodeAlert(contact, buffer, sizeof(buffer));
        checkTrue("contact alert encodes", length > 0);

        Alert decoded;
        checkEqual("contact alert decodes", "OK",
                   decodeResultName(decodeAlert(buffer, length, decoded)));
        checkEqual("contact alert kind", "contact", alertKindName(decoded.alertKind));
        checkTrue("contact alert confidence stays null", !decoded.hasConfidence);
        checkEqual("contact alert threat", "UNKNOWN", threatName(decoded.threat));
        checkEqual("contact alert band", "UNKNOWN", bandName(decoded.band));
    }

    // confidence 0 must remain distinguishable from confidence null, or the
    // whole nullable-confidence design is defeated.
    {
        Alert zero;
        alertInit(zero);
        zero.hasConfidence = true;
        zero.confidence = 0;

        uint8_t zeroBuffer[MAX_PAYLOAD_BYTES];
        const size_t zeroLength = encodeAlert(zero, zeroBuffer, sizeof(zeroBuffer));

        Alert absent;
        alertInit(absent);

        uint8_t absentBuffer[MAX_PAYLOAD_BYTES];
        const size_t absentLength = encodeAlert(absent, absentBuffer, sizeof(absentBuffer));

        checkNotEqual("confidence 0 encodes differently from null",
                      toHex(absentBuffer, absentLength), toHex(zeroBuffer, zeroLength));

        Alert decodedZero;
        decodeAlert(zeroBuffer, zeroLength, decodedZero);
        checkTrue("confidence 0 decodes as present", decodedZero.hasConfidence);
        checkEqual("confidence 0 decodes as 0", "0", confidenceText(decodedZero));

        Alert decodedAbsent;
        decodeAlert(absentBuffer, absentLength, decodedAbsent);
        checkTrue("absent confidence decodes as absent", !decodedAbsent.hasConfidence);
    }

    // Version gating: a retired-version packet must be rejected outright.
    {
        const uint8_t wrongVersion[] = { 0xA1, 0x01, 0x02 };
        Alert decoded;
        checkEqual("protocol_version 2 is rejected", "WRONG_VERSION",
                   decodeResultName(decodeAlert(wrongVersion, sizeof(wrongVersion), decoded)));

        const uint8_t noVersion[] = { 0xA1, 0x03, 0x01 };
        checkEqual("missing protocol_version is rejected", "WRONG_VERSION",
                   decodeResultName(decodeAlert(noVersion, sizeof(noVersion), decoded)));
    }

    // Malformed input must never yield a usable alert.
    {
        Alert decoded;

        const uint8_t missingFields[] = { 0xA1, 0x01, 0x03 };
        checkEqual("incomplete map is rejected", "MISSING_FIELD",
                   decodeResultName(decodeAlert(missingFields, sizeof(missingFields), decoded)));

        const uint8_t badEnum[] = { 0xA2, 0x01, 0x03, 0x06, 0x09 };
        checkEqual("out-of-range threat is rejected", "BAD_VALUE",
                   decodeResultName(decodeAlert(badEnum, sizeof(badEnum), decoded)));

        const uint8_t badConfidence[] = { 0xA2, 0x01, 0x03, 0x0A, 0x18, 0xC8 };
        checkEqual("confidence above 100 is rejected", "BAD_VALUE",
                   decodeResultName(decodeAlert(badConfidence, sizeof(badConfidence), decoded)));

        checkEqual("empty payload is rejected", "MALFORMED",
                   decodeResultName(decodeAlert(nullptr, 0, decoded)));

        const uint8_t notAMap[] = { 0x01 };
        checkEqual("non-map payload is rejected", "MALFORMED",
                   decodeResultName(decodeAlert(notAMap, sizeof(notAMap), decoded)));

        // Indefinite-length items are outside the accepted CBOR subset.
        const uint8_t indefinite[] = { 0xBF, 0x01, 0x03, 0xFF };
        checkTrue("indefinite-length map is rejected",
                  decodeAlert(indefinite, sizeof(indefinite), decoded) != DECODE_OK);
    }

    // Truncation at every length must be rejected, never decoded into a
    // plausible-but-wrong alert.
    {
        Alert full;
        alertInit(full);
        full.timestampMs = 12840;
        full.sequence = 1;
        full.threat = THREAT_FPV;
        full.severity = SEVERITY_HIGH;
        full.band = BAND_5_8;
        full.distance = DISTANCE_NEAR;
        full.hasConfidence = true;
        full.confidence = 87;
        alertSetDroneClass(full, "FPV");
        alertSetSource(full, "TTSKW07");

        uint8_t buffer[MAX_PAYLOAD_BYTES];
        const size_t length = encodeAlert(full, buffer, sizeof(buffer));

        bool anyTruncationAccepted = false;

        for (size_t cut = 1; cut < length; cut += 1) {
            Alert decoded;

            if (decodeAlert(buffer, cut, decoded) == DECODE_OK) {
                anyTruncationAccepted = true;
                printf("        truncation at %zu of %zu bytes was accepted\n", cut, length);
            }
        }

        checkTrue("no truncated packet decodes as OK", !anyTruncationAccepted);
    }

    // The encoder must refuse a buffer it cannot fill rather than emit a
    // partial map.
    {
        Alert alert;
        alertInit(alert);
        alertSetDroneClass(alert, "DJI_MAVIC");

        uint8_t tiny[8];
        checkEqual("undersized buffer yields no packet", "0",
                   std::to_string(encodeAlert(alert, tiny, sizeof(tiny))));
    }

    // Unknown keys from a future minor revision must be skipped, not fatal.
    {
        Alert alert;
        alertInit(alert);
        alert.timestampMs = 500;
        alert.sequence = 2;
        alert.threat = THREAT_DJI;

        uint8_t buffer[MAX_PAYLOAD_BYTES];
        const size_t length = encodeAlert(alert, buffer, sizeof(buffer));

        // Splice in key 99 with uint value 42 by rewriting the map header.
        // Both are encoded in the 1-byte-argument form (0x18 prefix): a bare
        // 0x2A would be CBOR major type 1, a negative integer, which is
        // correctly outside the accepted subset.
        std::vector<uint8_t> extended(buffer, buffer + length);
        extended[0] = static_cast<uint8_t>(0xA0 | ((extended[0] & 0x1F) + 1));
        extended.push_back(0x18);
        extended.push_back(99);
        extended.push_back(0x18);
        extended.push_back(42);

        Alert decoded;
        checkEqual("unknown key is skipped, not fatal", "OK",
                   decodeResultName(decodeAlert(extended.data(), extended.size(), decoded)));
        checkEqual("known fields survive an unknown key", "DJI", threatName(decoded.threat));
    }
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("usage: contract_test <ttskw07_raw_samples.txt> <expected_alerts.txt>\n");
        return 2;
    }

    printf("SKYSHIELD contract test (protocol_version %d)\n", PROTOCOL_VERSION);

    runRoundTrip(argv[1], argv[2]);
    runGuardrail();
    runCodec();

    printf("\n%d checks, %d failures\n", gChecks, gFailures);

    if (gFailures > 0) {
        printf("CONTRACT TEST FAILED\n");
        return 1;
    }

    printf("CONTRACT TEST PASSED\n");
    return 0;
}
