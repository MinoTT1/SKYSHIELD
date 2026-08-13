import Toybox.Lang;
import Toybox.Test;

// Contract tests for the Monkey C DW01 parser.
//
// These are the SAME fixtures and the SAME assertions as the C++ suite in
// tools/contract-test/dw01_contract_test.cpp. The point is not to test the
// port in isolation but to prove the two implementations agree, so that
// whichever architecture wins the behaviour is already pinned.
//
// Run with:  monkeyc --unit-test ... && monkeydo <prg> fenix7x -t
//
// NOT hardware-verified against a physical DW01. The vendor example is real;
// the rest are synthetic records built from the vendor's confirmed table.

// Shared counters so a run reports a total the way the C++ suite does.
(:test) var dw01Checks = 0;
(:test) var dw01Failures = 0;

// Test support. A (:test) CLASS is compiled into the unit-test build but is
// not enumerated as a test, unlike a module-level (:test) function -- which
// is why these are static methods rather than free functions.
(:test)
class DW01TestSupport {

    static function dw01ResetCounters() {
        dw01Checks = 0;
        dw01Failures = 0;
    }

    static function dw01CheckEqual(logger, what, expected, actual) {
        dw01Checks += 1;
    
        if (expected == null) {
            if (actual != null) {
                dw01Failures += 1;
                logger.error("FAIL " + what + ": expected null, got " + actual);
                return false;
            }
    
            return true;
        }
    
        if ((actual == null) || !expected.toString().equals(actual.toString())) {
            dw01Failures += 1;
            logger.error("FAIL " + what + ": expected " + expected + ", got " + actual);
            return false;
        }
    
        return true;
    }

    static function dw01CheckNotEqual(logger, what, forbidden, actual) {
        dw01Checks += 1;
    
        if ((actual != null) && forbidden.toString().equals(actual.toString())) {
            dw01Failures += 1;
            logger.error("FAIL " + what + ": must not be " + forbidden);
            return false;
        }
    
        return true;
    }

    static function dw01CheckTrue(logger, what, condition) {
        dw01Checks += 1;
    
        if (!condition) {
            dw01Failures += 1;
            logger.error("FAIL " + what);
            return false;
        }
    
        return true;
    }

    static function dw01Parse(record) {
        return DW01Parser.parseLine(record, 1000, 1);
    }

    static function dw01HexPair(value) {
        var digits = "0123456789ABCDEF";
        var high = (value / 16) % 16;
        var low = value % 16;
        return digits.substring(high, high + 1) + digits.substring(low, low + 1);
    }

    static function dw01Pad3(value) {
        if (value < 10) { return "00" + value; }
        if (value < 100) { return "0" + value; }
        return "" + value;
    }
}

// ---------------------------------------------------------------------------
// 1. The vendor's own example record
// ---------------------------------------------------------------------------
(:test)
function testDw01VendorExample(logger) {
    DW01TestSupport.dw01ResetCounters();

    var parsed = DW01TestSupport.dw01Parse("F5788R093T06C202");
    var alert = parsed[:alert];
    var diagnostics = parsed[:diagnostics];

    DW01TestSupport.dw01CheckEqual(logger, "vendor example parses", DW01_RESULT_OK, parsed[:result]);
    DW01TestSupport.dw01CheckEqual(logger, "F5788 -> 5788MHz", 5788, diagnostics.frequencyMhz);
    DW01TestSupport.dw01CheckEqual(logger, "R093 -> 93", 93, diagnostics.signalValue);
    DW01TestSupport.dw01CheckEqual(logger, "T06 -> 0x06", 6, diagnostics.typeCode);
    DW01TestSupport.dw01CheckTrue(logger, "T06 is a listed code", diagnostics.typeCodeRecognized);
    DW01TestSupport.dw01CheckEqual(logger, "0x06 -> DJI", "DJI", alert.threatType);
    DW01TestSupport.dw01CheckEqual(logger, "5788MHz -> 5.8GHz", "5.8GHz", alert.band);
    DW01TestSupport.dw01CheckEqual(logger, "R093 -> NEAR", "NEAR", alert.distanceLabel);
    DW01TestSupport.dw01CheckEqual(logger, "NEAR -> HIGH", "HIGH", alert.riskLevel);
    DW01TestSupport.dw01CheckEqual(logger, "confidence stays null", null, alert.confidencePercent);
    DW01TestSupport.dw01CheckEqual(logger, "model text from the vendor table",
        "DJI O3(DJI FPV, Mavic Air 2S, Mini 3 Pro)", alert.droneClass);
    DW01TestSupport.dw01CheckEqual(logger, "source label", "DW01", alert.source);
    DW01TestSupport.dw01CheckEqual(logger, "sensor type", "RF", alert.sensorType);
    DW01TestSupport.dw01CheckEqual(logger, "alert kind", "CLASSIFIED", alert.alertKind);
    DW01TestSupport.dw01CheckEqual(logger, "timestamp from the caller", 1000, alert.timestampMs);
    DW01TestSupport.dw01CheckEqual(logger, "detector_type_code carried", 6, alert.detectorTypeCode);

    // The C field is captured and never interpreted.
    DW01TestSupport.dw01CheckTrue(logger, "C field captured", diagnostics.hasCField);
    DW01TestSupport.dw01CheckEqual(logger, "C field verbatim", "202", diagnostics.cField);

    logger.debug("vendor example: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 2. Hex is parsed as hex -- the trap that would silently misclassify
// ---------------------------------------------------------------------------
(:test)
function testDw01HexNotDecimal(logger) {
    DW01TestSupport.dw01ResetCounters();

    // record, the two characters, hex value, decimal misreading, threat
    var cases = [
        ["F5788R093T10C202", "T10", 0x10, 10, "AUTEL"],
        ["F5788R093T11C202", "T11", 0x11, 11, "AUTEL"],
        ["F5788R093T12C202", "T12", 0x12, 12, "AUTEL"],
        ["F3320R093T20C202", "T20", 0x20, 20, "FPV"],
        ["F2412R064T30C130", "T30", 0x30, 30, "UNKNOWN"]
    ];

    for (var i = 0; i < cases.size(); i += 1) {
        var parsed = DW01TestSupport.dw01Parse(cases[i][0]);
        var tag = cases[i][1];

        DW01TestSupport.dw01CheckEqual(logger, tag + " parses", DW01_RESULT_OK, parsed[:result]);
        DW01TestSupport.dw01CheckEqual(logger, tag + " decodes as hex", cases[i][2], parsed[:diagnostics].typeCode);
        DW01TestSupport.dw01CheckEqual(logger, tag + " threat", cases[i][4], parsed[:alert].threatType);

        // Stated explicitly so the intent is unmissable to a future reader.
        DW01TestSupport.dw01CheckNotEqual(logger, tag + " is NOT read as decimal " + cases[i][3],
            cases[i][3], parsed[:diagnostics].typeCode);
    }

    // 'C' is a hex digit. A greedy hex read would swallow the C field.
    var greedy = DW01TestSupport.dw01Parse("F5788R093T06C202");
    DW01TestSupport.dw01CheckEqual(logger, "T is exactly two hex chars", 6, greedy[:diagnostics].typeCode);
    DW01TestSupport.dw01CheckNotEqual(logger, "T did not consume C202", 0x06C202, greedy[:diagnostics].typeCode);

    logger.debug("hex parsing: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 3. The full vendor table maps as documented
// ---------------------------------------------------------------------------
(:test)
function testDw01TypeTable(logger) {
    DW01TestSupport.dw01ResetCounters();

    // code, threat, listed
    var table = [
        [0x01, "DJI", true],
        [0x02, "DJI", true],
        [0x03, "DJI", true],
        [0x04, "DJI", true],
        [0x05, "DJI", true],
        [0x06, "DJI", true],
        [0x07, "DJI", true],
        [0x10, "AUTEL", true],
        [0x11, "AUTEL", true],
        [0x12, "AUTEL", true],
        [0x20, "FPV", true],
        [0x30, "UNKNOWN", true],   // WiFi, pending a protocol decision
        [0x00, "UNKNOWN", false]   // the device's own "unrecognized"
    ];

    for (var i = 0; i < table.size(); i += 1) {
        var code = table[i][0];
        var record = "F5788R093T" + DW01TestSupport.dw01HexPair(code) + "C202";
        var parsed = DW01TestSupport.dw01Parse(record);
        var tag = "0x" + DW01TestSupport.dw01HexPair(code);

        DW01TestSupport.dw01CheckEqual(logger, tag + " parses", DW01_RESULT_OK, parsed[:result]);
        DW01TestSupport.dw01CheckEqual(logger, tag + " threat", table[i][1], parsed[:alert].threatType);
        DW01TestSupport.dw01CheckEqual(logger, tag + " raw code carried", code, parsed[:alert].detectorTypeCode);
        DW01TestSupport.dw01CheckEqual(logger, tag + " listed flag", table[i][2], parsed[:diagnostics].typeCodeRecognized);
        DW01TestSupport.dw01CheckTrue(logger, tag + " model text present",
            (parsed[:alert].droneClass != null) && (parsed[:alert].droneClass.length() > 0));
        DW01TestSupport.dw01CheckEqual(logger, tag + " model text matches the table",
            DW01Parser.modelTextFromCode(code), parsed[:alert].droneClass);
        DW01TestSupport.dw01CheckNotEqual(logger, tag + " severity never CRITICAL", "CRITICAL", parsed[:alert].riskLevel);
    }

    logger.debug("type table: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 4. Negative guardrails -- the mistakes that would be invisible downstream
// ---------------------------------------------------------------------------
(:test)
function testDw01Guardrails(logger) {
    DW01TestSupport.dw01ResetCounters();

    // AUTEL must never become DJI. A false vendor attribution on a threat
    // display is worse than saying nothing.
    var autel = ["F5788R093T10C202", "F5788R093T11C202", "F5788R093T12C202"];

    for (var i = 0; i < autel.size(); i += 1) {
        var alert = DW01TestSupport.dw01Parse(autel[i])[:alert];
        DW01TestSupport.dw01CheckEqual(logger, "AUTEL stays AUTEL", "AUTEL", alert.threatType);
        DW01TestSupport.dw01CheckNotEqual(logger, "AUTEL never becomes DJI", "DJI", alert.threatType);
        DW01TestSupport.dw01CheckNotEqual(logger, "AUTEL never becomes FPV", "FPV", alert.threatType);
    }

    // WiFi (0x30) must not be coerced. Parrot and Tello are not DJI.
    var wifi = DW01TestSupport.dw01Parse("F2412R064T30C130");
    DW01TestSupport.dw01CheckNotEqual(logger, "WiFi is NOT coerced to DJI", "DJI", wifi[:alert].threatType);
    DW01TestSupport.dw01CheckNotEqual(logger, "WiFi is NOT coerced to FPV", "FPV", wifi[:alert].threatType);
    DW01TestSupport.dw01CheckNotEqual(logger, "WiFi is NOT coerced to AUTEL", "AUTEL", wifi[:alert].threatType);
    DW01TestSupport.dw01CheckEqual(logger, "WiFi degrades to UNKNOWN", "UNKNOWN", wifi[:alert].threatType);
    DW01TestSupport.dw01CheckEqual(logger, "WiFi raw code 0x30 preserved", 48, wifi[:alert].detectorTypeCode);
    DW01TestSupport.dw01CheckEqual(logger, "WiFi model text preserved",
        "WiFi(Phantom 3S, SPARK, Tello, PARROT series)", wifi[:alert].droneClass);

    // An unlisted code degrades without crashing and without guessing.
    var unlisted = [0x08, 0x09, 0x13, 0x21, 0x31, 0x40, 0x99, 0xFF];

    for (var i = 0; i < unlisted.size(); i += 1) {
        var code = unlisted[i];
        var parsed = DW01TestSupport.dw01Parse("F5788R093T" + DW01TestSupport.dw01HexPair(code) + "C202");
        var tag = "unlisted 0x" + DW01TestSupport.dw01HexPair(code);

        DW01TestSupport.dw01CheckEqual(logger, tag + " still parses", DW01_RESULT_OK, parsed[:result]);
        DW01TestSupport.dw01CheckEqual(logger, tag + " degrades to UNKNOWN", "UNKNOWN", parsed[:alert].threatType);
        DW01TestSupport.dw01CheckTrue(logger, tag + " flagged unlisted", !parsed[:diagnostics].typeCodeRecognized);
        DW01TestSupport.dw01CheckEqual(logger, tag + " raw code retained", code, parsed[:alert].detectorTypeCode);
        DW01TestSupport.dw01CheckEqual(logger, tag + " no model text invented", "", parsed[:alert].droneClass);
    }

    // Bands are not force-fitted. The DW01 sweeps 0-8000MHz, so out-of-band
    // frequencies are ordinary traffic and must degrade, not snap to a band.
    var bands = [
        ["F1250R093T01C202", "1.2GHz"],
        ["F2419R093T02C202", "2.4GHz"],
        ["F3320R093T20C202", "3.3GHz"],
        ["F5788R093T06C202", "5.8GHz"],
        ["F0900R093T06C202", "UNKNOWN"],
        ["F1800R093T06C202", "UNKNOWN"],
        ["F4000R093T06C202", "UNKNOWN"],
        ["F7900R093T06C202", "UNKNOWN"],
        ["F0000R093T06C202", "UNKNOWN"]
    ];

    for (var i = 0; i < bands.size(); i += 1) {
        var parsed = DW01TestSupport.dw01Parse(bands[i][0]);
        DW01TestSupport.dw01CheckEqual(logger, bands[i][0] + " parses", DW01_RESULT_OK, parsed[:result]);
        DW01TestSupport.dw01CheckEqual(logger, bands[i][0] + " band", bands[i][1], parsed[:alert].band);
    }

    // Severity can never reach CRITICAL from a single record.
    var signals = [0, 1, 39, 40, 69, 70, 100, 128, 200];

    for (var i = 0; i < signals.size(); i += 1) {
        var record = "F5788R" + DW01TestSupport.dw01Pad3(signals[i]) + "T06C202";
        var parsed = DW01TestSupport.dw01Parse(record);

        if (parsed[:result].equals(DW01_RESULT_OK)) {
            DW01TestSupport.dw01CheckNotEqual(logger, "severity never CRITICAL at R=" + signals[i],
                "CRITICAL", parsed[:alert].riskLevel);
        }
    }

    // Confidence is absent, never a fabricated zero.
    var confidence = DW01TestSupport.dw01Parse("F5788R093T06C202");
    DW01TestSupport.dw01CheckEqual(logger, "confidence is null", null, confidence[:alert].confidencePercent);
    DW01TestSupport.dw01CheckNotEqual(logger, "confidence is not a fabricated 0", 0, confidence[:alert].confidencePercent);

    logger.debug("guardrails: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 5. The C field, and malformed input
// ---------------------------------------------------------------------------
(:test)
function testDw01CFieldAndMalformed(logger) {
    DW01TestSupport.dw01ResetCounters();

    // A missing C must NOT break the detection: its meaning is unknown, so it
    // cannot be a precondition for reporting a drone.
    var noC = DW01TestSupport.dw01Parse("F5788R093T06");
    DW01TestSupport.dw01CheckEqual(logger, "record without C still parses", DW01_RESULT_OK, noC[:result]);
    DW01TestSupport.dw01CheckTrue(logger, "C absent recorded as absent", !noC[:diagnostics].hasCField);
    DW01TestSupport.dw01CheckEqual(logger, "threat unaffected by a missing C", "DJI", noC[:alert].threatType);

    // An empty C is captured as empty, not treated as an error.
    var emptyC = DW01TestSupport.dw01Parse("F5788R093T06C");
    DW01TestSupport.dw01CheckEqual(logger, "record with empty C parses", DW01_RESULT_OK, emptyC[:result]);
    DW01TestSupport.dw01CheckTrue(logger, "empty C still marked present", emptyC[:diagnostics].hasCField);
    DW01TestSupport.dw01CheckEqual(logger, "empty C is empty", "", emptyC[:diagnostics].cField);

    // An unexpected C value is captured verbatim, never validated away.
    var cCases = [
        ["F5788R093T06C202", "202"],
        ["F5788R093T06C000", "000"],
        ["F5788R093T06C99999", "99999"],
        ["F5788R093T06CABC", "ABC"]
    ];

    for (var i = 0; i < cCases.size(); i += 1) {
        var parsed = DW01TestSupport.dw01Parse(cCases[i][0]);
        DW01TestSupport.dw01CheckEqual(logger, "C captured verbatim: " + cCases[i][1],
            cCases[i][1], parsed[:diagnostics].cField);
    }

    // A GENUINE AMBIGUITY of the fixed-width format, pinned so it stays a
    // known property: "T6C202" is indistinguishable from code 0x6C with no C
    // field. The parser takes the fixed-width reading, the vendor's stated
    // format, and does NOT guess that T06 was meant.
    var ambiguous = DW01TestSupport.dw01Parse("F5788R093T6C202");
    DW01TestSupport.dw01CheckEqual(logger, "T6C202 parses under the fixed-width rule",
        DW01_RESULT_OK, ambiguous[:result]);
    DW01TestSupport.dw01CheckEqual(logger, "T6C202 reads as 0x6C not 0x06", 108, ambiguous[:diagnostics].typeCode);
    DW01TestSupport.dw01CheckEqual(logger, "0x6C is unlisted so it degrades", "UNKNOWN", ambiguous[:alert].threatType);
    DW01TestSupport.dw01CheckTrue(logger, "no C field after a two-char code", !ambiguous[:diagnostics].hasCField);

    // Noise is skipped quietly; broken records are reported, not silently
    // accepted as a detection.
    var bad = [
        ["", DW01_RESULT_NOT_A_DETECTION],
        ["banner: DW01 v1.0 ready", DW01_RESULT_NOT_A_DETECTION],
        ["   ", DW01_RESULT_NOT_A_DETECTION],
        ["X5788R093T06C202", DW01_RESULT_NOT_A_DETECTION],
        ["FR093T06C202", DW01_RESULT_MALFORMED],
        ["F5788T06C202", DW01_RESULT_MALFORMED],
        ["F5788R093X06C202", DW01_RESULT_MALFORMED],
        ["F5788R093T0", DW01_RESULT_MALFORMED],
        ["F5788R093TZZC202", DW01_RESULT_MALFORMED]
    ];

    for (var i = 0; i < bad.size(); i += 1) {
        DW01TestSupport.dw01CheckEqual(logger, "\"" + bad[i][0] + "\" -> " + bad[i][1],
            bad[i][1], DW01TestSupport.dw01Parse(bad[i][0])[:result]);
    }

    // A null input must not crash the parser.
    DW01TestSupport.dw01CheckEqual(logger, "null input handled",
        DW01_RESULT_NOT_A_DETECTION, DW01TestSupport.dw01Parse(null)[:result]);

    // Padding is tolerated: a BLE push may arrive with CR/LF or spaces.
    var padded = DW01TestSupport.dw01Parse("  F5788R093T06C202  \r\n");
    DW01TestSupport.dw01CheckEqual(logger, "padded record parses", DW01_RESULT_OK, padded[:result]);
    DW01TestSupport.dw01CheckEqual(logger, "padded record still DJI", "DJI", padded[:alert].threatType);

    // R above the vendor's stated maximum is carried and flagged, not dropped.
    var high = DW01TestSupport.dw01Parse("F5788R200T06C202");
    DW01TestSupport.dw01CheckEqual(logger, "R200 still parses", DW01_RESULT_OK, high[:result]);
    DW01TestSupport.dw01CheckEqual(logger, "R200 value retained", 200, high[:diagnostics].signalValue);
    DW01TestSupport.dw01CheckTrue(logger, "R200 flagged out of range", high[:diagnostics].signalOutOfRange);

    var atMax = DW01TestSupport.dw01Parse("F5788R128T06C202");
    DW01TestSupport.dw01CheckTrue(logger, "R128 is at the maximum, not flagged",
        !atMax[:diagnostics].signalOutOfRange);

    logger.debug("C field and malformed: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 6. Cross-implementation agreement
// ---------------------------------------------------------------------------
// Every record in esp32-bridge/test_samples/dw01_raw_samples.txt with the
// threat, band, distance and raw code the C++ parser produces for it. The
// expected column is the C++ implementation's OUTPUT, captured from a run --
// not restated intent. If the two ever diverge, this fails.
(:test)
function testDw01MatchesCppReference(logger) {
    DW01TestSupport.dw01ResetCounters();

    // record, threat, band, distance, severity, raw code, kind
    var reference = [
        ["F5788R093T06C202", "DJI",     "5.8GHz",  "NEAR", "HIGH",   6,   "CLASSIFIED"],
        ["F5788R093T01C202", "DJI",     "5.8GHz",  "NEAR", "HIGH",   1,   "CLASSIFIED"],
        ["F2419R043T02C118", "DJI",     "2.4GHz",  "MID",  "MEDIUM", 2,   "CLASSIFIED"],
        ["F1250R120T03C077", "DJI",     "1.2GHz",  "NEAR", "HIGH",   3,   "CLASSIFIED"],
        ["F5773R046T04C200", "DJI",     "5.8GHz",  "MID",  "MEDIUM", 4,   "CLASSIFIED"],
        ["F5765R110T05C201", "DJI",     "5.8GHz",  "NEAR", "HIGH",   5,   "CLASSIFIED"],
        ["F5788R012T07C203", "DJI",     "5.8GHz",  "FAR",  "LOW",    7,   "CLASSIFIED"],
        ["F2440R088T10C150", "AUTEL",   "2.4GHz",  "NEAR", "HIGH",   16,  "CLASSIFIED"],
        ["F5768R042T11C160", "AUTEL",   "5.8GHz",  "MID",  "MEDIUM", 17,  "CLASSIFIED"],
        ["F5810R127T12C199", "AUTEL",   "5.8GHz",  "NEAR", "HIGH",   18,  "CLASSIFIED"],
        ["F3320R093T20C202", "FPV",     "3.3GHz",  "NEAR", "HIGH",   32,  "CLASSIFIED"],
        ["F2412R064T30C130", "UNKNOWN", "2.4GHz",  "MID",  "MEDIUM", 48,  "CLASSIFIED"],
        ["F5788R093T00C202", "UNKNOWN", "5.8GHz",  "NEAR", "HIGH",   0,   "CLASSIFIED"],
        ["F7900R055T06C202", "DJI",     "UNKNOWN", "MID",  "MEDIUM", 6,   "CLASSIFIED"],
        ["F0000R000T00C000", "UNKNOWN", "UNKNOWN", "FAR",  "LOW",    0,   "CONTACT"]
    ];

    for (var i = 0; i < reference.size(); i += 1) {
        var parsed = DW01TestSupport.dw01Parse(reference[i][0]);
        var tag = "cpp[" + i + "] " + reference[i][0];

        if (!DW01TestSupport.dw01CheckEqual(logger, tag + " parses", DW01_RESULT_OK, parsed[:result])) {
            continue;
        }

        DW01TestSupport.dw01CheckEqual(logger, tag + " threat", reference[i][1], parsed[:alert].threatType);
        DW01TestSupport.dw01CheckEqual(logger, tag + " band", reference[i][2], parsed[:alert].band);
        DW01TestSupport.dw01CheckEqual(logger, tag + " distance", reference[i][3], parsed[:alert].distanceLabel);
        DW01TestSupport.dw01CheckEqual(logger, tag + " severity", reference[i][4], parsed[:alert].riskLevel);
        DW01TestSupport.dw01CheckEqual(logger, tag + " raw code", reference[i][5], parsed[:alert].detectorTypeCode);
        DW01TestSupport.dw01CheckEqual(logger, tag + " kind", reference[i][6], parsed[:alert].alertKind);
        DW01TestSupport.dw01CheckEqual(logger, tag + " confidence null", null, parsed[:alert].confidencePercent);
    }

    logger.debug("cpp agreement: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 7. The parser is dormant
// ---------------------------------------------------------------------------
(:test)
function testDw01IsDisabledByDefault(logger) {
    DW01TestSupport.dw01ResetCounters();

    DW01TestSupport.dw01CheckTrue(logger, "DW01_PARSER_ENABLED is OFF in the shipping build",
        DW01_PARSER_ENABLED == false);

    logger.debug("dormancy: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// Formats a byte as two uppercase hex characters, so test records are built
// the same way the device emits them.

