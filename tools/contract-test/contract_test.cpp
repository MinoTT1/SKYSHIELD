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

void runRoundTrip(const std::string& samplesPath, const std::string& fixturePath,
                  const char* label) {
    printf("\n[1] ROUND TRIP  %s\n", label);

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

        if (expected.size() < 12) {
            fail("fixture row " + std::to_string(i) + " is malformed", "12 fields",
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

        // The numeric T code is the primary classification input, so it is
        // asserted alongside whether the parser recognized it.
        checkEqual(label + " t_code", expected[8],
                   std::to_string(static_cast<int>(diagnostics.typeCode)));
        checkEqual(label + " t_code recognized", expected[9],
                   diagnostics.typeCodeRecognized ? "known" : "unknown");

        // Locking the exact bytes means any change to key assignment, enum
        // numbering or integer encoding fails loudly instead of silently
        // shipping a format the watch cannot read.
        checkEqual(label + " CBOR bytes", expected[11], toHex(buffer, length));

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
        checkEqual(label + " drone_class", expected[10],
                   decoded.hasDroneClass ? std::string(decoded.droneClass) : std::string("-"));

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

// Parses one line and reports both the decoded alert and the parser
// diagnostics, so guardrails can assert on the t_code as well as the wire.
bool decodeSampleLineFull(const char* line, Alert& decoded, TTSKW07Diagnostics& diagnostics) {
    Alert parsed;

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
    printf("\n[2] GUARDRAIL  classification rules that must not regress\n");

    // Real vendor lines, so the guardrail exercises the actual format.
    const char* analogLine  = "06 11:25:36   F:3320MHz   R:093   T:20   FM Analog(DIY FPV, Aircraft model)";
    const char* o3Line      = "06 11:25:48   F:2419MHz   R:043   T:06   DJI O3(FPV, Mavic Air 2s, Mavic Mini 3 Pro)";
    const char* o3PlusLine  = "05-09 09:28:00 F:5773MHz  R:046   T:05   DJI O3+(Mavic 3 series, AVATA)";
    const char* autelLite   = "06 14:16:22   F:5768MHz   R:042   T:11   SkyLink(AUTEL Lite/Nano)";
    const char* autelEvo    = "06 14:26:30   F:5768MHz   R:046   T:12   SkyLink(AUTEL EVO2 Pro)";
    const char* unknownLine = "06 11:34:56   F:2409MHz   R:023   T:07   Unknown";

    Alert alert;
    TTSKW07Diagnostics diagnostics;

    // --- #1 confidence is null, never 0 -------------------------------------
    // The device reports no confidence. "CONF 0%" on a threat HUD reads as
    // "certainly not a threat" when the truth is "we were told nothing".
    if (decodeSampleLineFull(o3Line, alert, diagnostics)) {
        checkTrue("#1 confidence is absent", !alert.hasConfidence);
        checkNotEqual("#1 confidence must not be a number", "0", confidenceText(alert));
        checkEqual("#1 confidence reads null", "null", confidenceText(alert));
    } else {
        fail("#1 DJI O3 line decodes", "decoded", "failed");
    }

    // --- #2 no single detector line may reach CRITICAL ----------------------
    // Escalation is the watch's job, based on track persistence the bridge
    // does not have. Raising severity because classification failed would
    // manufacture false positives.
    checkTrue("#2 default severity policy can never emit CRITICAL",
              ttskw07PolicyAvoidsCritical(TTSKW07_DEFAULT_SEVERITY_POLICY));

    {
        // Sweep the whole R range, including values above the 0-100 the vendor
        // implies and the 117 actually observed in a capture.
        const int signals[] = { 0, 23, 42, 46, 70, 93, 100, 117, 250 };

        for (size_t i = 0; i < (sizeof(signals) / sizeof(signals[0])); i += 1) {
            char line[128];
            snprintf(line, sizeof(line),
                     "06 11:25:36   F:2419MHz   R:%03d   T:20   FM Analog(DIY FPV)", signals[i]);

            if (decodeSampleLineFull(line, alert, diagnostics)) {
                checkNotEqual(std::string("#2 R=") + std::to_string(signals[i]) +
                              " must not be CRITICAL", "CRITICAL", severityName(alert.severity));
            }
        }
    }

    if (decodeSampleLineFull(unknownLine, alert, diagnostics)) {
        checkNotEqual("#2 unclassified T:07 must not be CRITICAL",
                      "CRITICAL", severityName(alert.severity));
        checkEqual("#2 unclassified T:07 threat stays UNKNOWN", "UNKNOWN", threatName(alert.threat));
    }

    // --- #3 Autel is first-class, and never DJI ----------------------------
    // As of protocol version 4 AUTEL is its own threat value. It must decode as
    // AUTEL: not DJI, which would be a false vendor claim, and no longer
    // UNKNOWN, which was the pre-v4 compromise that lost real information.
    if (decodeSampleLineFull(autelLite, alert, diagnostics)) {
        checkEqual("#3 T:11 decodes as AUTEL", "AUTEL", threatName(alert.threat));
        checkNotEqual("#3 T:11 must not be DJI", "DJI", threatName(alert.threat));
        checkNotEqual("#3 T:11 must not fall back to UNKNOWN",
                      "UNKNOWN", threatName(alert.threat));
        checkEqual("#3 T:11 vendor text survives in drone_class", "SkyLink(AUTEL Lite/Nano)",
                   alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
    } else {
        fail("#3 AUTEL Lite line decodes", "decoded", "failed");
    }

    if (decodeSampleLineFull(autelEvo, alert, diagnostics)) {
        checkEqual("#3 T:12 decodes as AUTEL", "AUTEL", threatName(alert.threat));
        checkNotEqual("#3 T:12 must not be DJI", "DJI", threatName(alert.threat));
        checkNotEqual("#3 T:12 must not fall back to UNKNOWN",
                      "UNKNOWN", threatName(alert.threat));
        checkEqual("#3 T:12 vendor text survives in drone_class", "SkyLink(AUTEL EVO2 Pro)",
                   alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
    }

    // AUTEL must survive a full encode/decode round trip as a distinct value,
    // not collapse into a neighbouring enum.
    {
        Alert autel;
        alertInit(autel);
        autel.threat = THREAT_AUTEL;

        uint8_t buffer[MAX_PAYLOAD_BYTES];
        const size_t length = encodeAlert(autel, buffer, sizeof(buffer));

        Alert decoded;
        checkEqual("#3 AUTEL round-trips through the codec", "OK",
                   decodeResultName(decodeAlert(buffer, length, decoded)));
        checkEqual("#3 AUTEL survives the round trip", "AUTEL", threatName(decoded.threat));
    }

    // --- #4 model detail is preserved verbatim ------------------------------
    // The numeric code identifies the family; only the text carries the model.
    if (decodeSampleLineFull(o3PlusLine, alert, diagnostics)) {
        checkEqual("#4 O3+ description preserved verbatim", "DJI O3+(Mavic 3 series, AVATA)",
                   alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
        checkEqual("#4 O3+ threat family is DJI", "DJI", threatName(alert.threat));
    } else {
        fail("#4 DJI O3+ line decodes", "decoded", "failed");
    }

    if (decodeSampleLineFull(analogLine, alert, diagnostics)) {
        checkEqual("#4 analog FPV description preserved", "FM Analog(DIY FPV, Aircraft model)",
                   alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
        checkEqual("#4 T:20 maps to FPV", "FPV", threatName(alert.threat));
    }

    // --- #5 an unrecognized t_code degrades, never guesses -------------------
    // A future firmware revision will emit codes this table has never seen.
    // That must not crash, must not fail the line, and must not be inferred
    // from the description text.
    {
        const int unknownCodes[] = { 0, 1, 13, 42, 99, 255 };

        for (size_t i = 0; i < (sizeof(unknownCodes) / sizeof(unknownCodes[0])); i += 1) {
            char line[160];
            // Description deliberately says "DJI" to prove the text is not used
            // to guess a classification the code did not provide.
            snprintf(line, sizeof(line),
                     "06 12:02:10   F:2419MHz   R:061   T:%02d   DJI Something(unlisted)",
                     unknownCodes[i]);

            const std::string tag = "#5 T:" + std::to_string(unknownCodes[i]);

            if (!decodeSampleLineFull(line, alert, diagnostics)) {
                fail(tag + " still parses", "parsed", "rejected");
                continue;
            }

            checkEqual(tag + " degrades to UNKNOWN", "UNKNOWN", threatName(alert.threat));
            checkNotEqual(tag + " must not be guessed as DJI from text",
                          "DJI", threatName(alert.threat));
            checkEqual(tag + " raw code is retained", std::to_string(unknownCodes[i]),
                       std::to_string(static_cast<int>(diagnostics.typeCode)));

            // The raw code must reach the WATCH, not just the bridge log: it
            // is the only identifier of an undocumented protocol, and what
            // makes a field report to the vendor actionable.
            checkTrue(tag + " detector_type_code is present on the wire",
                      alert.hasDetectorTypeCode);
            checkEqual(tag + " detector_type_code carries the raw value",
                       std::to_string(unknownCodes[i]),
                       std::to_string(static_cast<int>(alert.detectorTypeCode)));
            checkTrue(tag + " is flagged unrecognized", !diagnostics.typeCodeRecognized);
            checkEqual(tag + " description is retained", "DJI Something(unlisted)",
                       alert.hasDroneClass ? std::string(alert.droneClass) : std::string("-"));
        }
    }

    // Every documented code must still be recognized, so a table edit that
    // drops one is caught.
    {
        const int knownCodes[] = { 2, 5, 6, 7, 11, 12, 20 };

        for (size_t i = 0; i < (sizeof(knownCodes) / sizeof(knownCodes[0])); i += 1) {
            checkTrue("#5 documented T:" + std::to_string(knownCodes[i]) + " is recognized",
                      ttskw07IsKnownTypeCode(static_cast<uint16_t>(knownCodes[i])));
        }
    }

    // --- #6 band is never force-fitted --------------------------------------
    // A frequency outside every known band must degrade to UNKNOWN rather than
    // snapping to the nearest one, which would invent a band the device never
    // reported.
    {
        struct FrequencyCase { int megahertz; const char* band; };

        const FrequencyCase cases[] = {
            { 3320, "3.3GHz" },   // real capture
            { 2419, "2.4GHz" },   // real capture
            { 5773, "5.8GHz" },   // real capture
            { 5930, "5.8GHz" },   // real capture, above the nominal 5900
            {  868, "UNKNOWN" },  // ISM/LoRa, not a drone video band
            { 1575, "UNKNOWN" },  // GPS L1
            { 4000, "UNKNOWN" },  // between 3.3 and 5.8
            { 7000, "UNKNOWN" },  // above everything
            {    0, "UNKNOWN" }
        };

        for (size_t i = 0; i < (sizeof(cases) / sizeof(cases[0])); i += 1) {
            char line[128];
            snprintf(line, sizeof(line),
                     "06 11:25:36   F:%04dMHz   R:061   T:06   DJI O3(test)", cases[i].megahertz);

            const std::string tag = "#6 F:" + std::to_string(cases[i].megahertz) + "MHz";

            if (decodeSampleLineFull(line, alert, diagnostics)) {
                checkEqual(tag + " band", cases[i].band, bandName(alert.band));
            } else {
                fail(tag + " parses", "parsed", "rejected");
            }
        }
    }

    // --- #7 the device timestamp never drives timing ------------------------
    // Captures show it unset (00-01-01) or plainly wrong. The alert's
    // timestamp_ms must come from the caller's monotonic clock regardless.
    {
        const char* unsetClock =
            "00-01-01 17:58:38 F:5930MHz R:117  T:07   Unknown";

        Alert parsed;
        TTSKW07Diagnostics local;

        if (ttskw07ParseLine(unsetClock, 4242, 9, parsed, local) == TTSKW07_OK) {
            checkEqual("#7 timestamp_ms comes from the caller, not the device",
                       "4242", std::to_string(parsed.timestampMs));
            checkEqual("#7 device clock text is captured for the log",
                       "00-01-01 17:58:38", std::string(local.timestamp));
        } else {
            fail("#7 unset-clock line parses", "parsed", "rejected");
        }
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

        // v3 packets predate AUTEL and detector_type_code, so a v4 decoder
        // must reject them rather than silently misreading a threat value.
        const uint8_t version3[] = { 0xA1, 0x01, 0x03 };
        checkEqual("protocol_version 3 is rejected", "WRONG_VERSION",
                   decodeResultName(decodeAlert(version3, sizeof(version3), decoded)));

        const uint8_t noVersion[] = { 0xA1, 0x03, 0x01 };
        checkEqual("missing protocol_version is rejected", "WRONG_VERSION",
                   decodeResultName(decodeAlert(noVersion, sizeof(noVersion), decoded)));
    }

    // Malformed input must never yield a usable alert.
    {
        Alert decoded;

        const uint8_t missingFields[] = { 0xA1, 0x01, 0x04 };
        checkEqual("incomplete map is rejected", "MISSING_FIELD",
                   decodeResultName(decodeAlert(missingFields, sizeof(missingFields), decoded)));

        const uint8_t badEnum[] = { 0xA2, 0x01, 0x04, 0x06, 0x09 };
        checkEqual("out-of-range threat is rejected", "BAD_VALUE",
                   decodeResultName(decodeAlert(badEnum, sizeof(badEnum), decoded)));

        const uint8_t badConfidence[] = { 0xA2, 0x01, 0x04, 0x0A, 0x18, 0xC8 };
        checkEqual("confidence above 100 is rejected", "BAD_VALUE",
                   decodeResultName(decodeAlert(badConfidence, sizeof(badConfidence), decoded)));

        checkEqual("empty payload is rejected", "MALFORMED",
                   decodeResultName(decodeAlert(nullptr, 0, decoded)));

        const uint8_t notAMap[] = { 0x01 };
        checkEqual("non-map payload is rejected", "MALFORMED",
                   decodeResultName(decodeAlert(notAMap, sizeof(notAMap), decoded)));

        // Indefinite-length items are outside the accepted CBOR subset.
        const uint8_t indefinite[] = { 0xBF, 0x01, 0x04, 0xFF };
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
    if (argc < 5) {
        printf("usage: contract_test <raw_samples.txt> <expected_alerts.txt> "
               "<edge_cases.txt> <expected_edge_cases.txt>\n");
        return 2;
    }

    printf("SKYSHIELD contract test (protocol_version %d)\n", PROTOCOL_VERSION);

    runRoundTrip(argv[1], argv[2], "real vendor captures");
    runRoundTrip(argv[3], argv[4], "synthetic edge cases");
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
