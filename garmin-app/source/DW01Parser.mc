import Toybox.Lang;

// Monkey C port of the DW01 record parser.
//
// ===========================================================================
// DORMANT. NOTHING CALLS THIS.
// ===========================================================================
// Groundwork for Architecture A, where the watch connects straight to the
// Tatusky DW01 over BLE and there is no ESP32 in the path. That architecture
// is NOT confirmed, the device has NOT arrived, and no BLE client for it
// exists (the service and characteristic UUIDs are still unknown).
//
// This file is compiled but unreachable: no active code references it. The
// existing BLE -> CBOR -> AlertModel chain is untouched and remains the only
// live path. DW01_PARSER_ENABLED below is the gate any future adapter must
// check before feeding this anything.
//
// ===========================================================================
// PORTED FROM esp32-bridge/include/DW01Parser.h
// ===========================================================================
// The C++ version is the reference implementation and is covered by 706
// contract checks plus 9 mutation proofs. This port mirrors it
// decision-for-decision. Where Monkey C forced a different implementation the
// difference is marked "PORT NOTE" and the OUTPUT is identical.
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
// THE HEX TRAP: T is hex. T10 is 0x10 = AUTEL EVO 2, not decimal 10. Reading
// it as decimal does not crash -- it produces a plausible alert with the wrong
// threat, which nothing downstream could catch. A second trap: 'C' is itself a
// valid hex digit, so a greedy read of "T06C202" yields 0x06C202. T is read as
// EXACTLY two characters.
//
// Full format notes and the vendor table: docs/dw01-format.md

// The gate for any future DW01 adapter. OFF: the watch's live behaviour is
// exactly the stable baseline's.
//
// Note this flag is belt-and-braces. The real guarantee of dormancy is that
// no active code path references this file at all.
const DW01_PARSER_ENABLED = false;

const DW01_RESULT_OK = "OK";
const DW01_RESULT_NOT_A_DETECTION = "NOT_A_DETECTION";
const DW01_RESULT_MALFORMED = "MALFORMED";

const DW01_MAX_LINE = 120;
const DW01_SIGNAL_MAX = 128;

// Distance thresholds, matching DW01_DEFAULT_SIGNAL_POLICY in the C++ parser.
const DW01_SIGNAL_NEAR_MIN = 70;
const DW01_SIGNAL_MID_MIN = 40;

// Everything the raw record carried, including what AlertModel has no field
// for. Kept so the source data can be logged faithfully.
//
// PORT NOTE: the C++ version fills a caller-owned struct. Monkey C has no
// output parameters, so this is a class the parser allocates and returns
// inside its result dictionary. Same fields, same meanings.
class DW01Diagnostics {
    var hasFrequency;
    var frequencyMhz;
    var hasSignal;
    var signalValue;        // R, raw
    var signalOutOfRange;   // R exceeded the vendor's stated 0-128
    var hasTypeCode;
    var typeCode;           // T, already hex-decoded
    var typeCodeRecognized;
    var hasCField;
    var cField;             // verbatim; meaning unknown
    var cFieldTruncated;

    function initialize() {
        hasFrequency = false;
        frequencyMhz = 0;
        hasSignal = false;
        signalValue = 0;
        signalOutOfRange = false;
        hasTypeCode = false;
        typeCode = 0;
        typeCodeRecognized = false;
        hasCField = false;
        cField = "";
        // PORT NOTE: the C++ parser copies C into a fixed 16-byte buffer and
        // can truncate. Monkey C strings grow, so truncation cannot happen and
        // this is always false. Kept so both diagnostics shapes match.
        cFieldTruncated = false;
    }
}

class DW01Parser {

    // ---- character classification -----------------------------------------
    //
    // PORT NOTE: the C++ parser does char arithmetic (ch - '0'). Monkey C's
    // Char arithmetic is awkward and its behaviour across SDK versions is not
    // worth relying on for a safety-critical mapping, so both helpers use
    // explicit comparison instead. Returns -1 for "not a digit", which is the
    // same information the C++ bool-plus-out-parameter carries.

    static function digitValue(ch) {
        if (ch == '0') { return 0; }
        if (ch == '1') { return 1; }
        if (ch == '2') { return 2; }
        if (ch == '3') { return 3; }
        if (ch == '4') { return 4; }
        if (ch == '5') { return 5; }
        if (ch == '6') { return 6; }
        if (ch == '7') { return 7; }
        if (ch == '8') { return 8; }
        if (ch == '9') { return 9; }
        return -1;
    }

    static function hexValue(ch) {
        var decimal = digitValue(ch);

        if (decimal >= 0) {
            return decimal;
        }

        if ((ch == 'A') || (ch == 'a')) { return 10; }
        if ((ch == 'B') || (ch == 'b')) { return 11; }
        if ((ch == 'C') || (ch == 'c')) { return 12; }
        if ((ch == 'D') || (ch == 'd')) { return 13; }
        if ((ch == 'E') || (ch == 'e')) { return 14; }
        if ((ch == 'F') || (ch == 'f')) { return 15; }
        return -1;
    }

    static function isTrimmable(ch) {
        return (ch == ' ') || (ch == '\t') || (ch == '\r') || (ch == '\n');
    }

    // ---- the vendor table --------------------------------------------------
    //
    // OFFICIAL TYPE CODE TABLE -- VENDOR CONFIRMED (Kawhi, Tatusky).
    // Codes are hex. Identical to dw01IsKnownTypeCode / dw01ThreatFromCode /
    // dw01ModelTextFromCode in the C++ parser.

    static function isKnownTypeCode(typeCode) {
        if ((typeCode >= 0x01) && (typeCode <= 0x07)) { return true; }
        if ((typeCode >= 0x10) && (typeCode <= 0x12)) { return true; }
        if (typeCode == 0x20) { return true; }
        if (typeCode == 0x30) { return true; }

        // 0x00 is the device's own "Unrecognized" marker. It is a value we
        // understand, but it identifies nothing, so it is not "known".
        return false;
    }

    // WiFi (0x30) maps to UNKNOWN and NOT to DJI. The WiFi group contains
    // Parrot and Tello, which are not DJI aircraft, so folding them into DJI
    // would be a false vendor attribution on a threat display. Adding a
    // first-class WiFi threat is a protocol change awaiting a decision.
    static function threatFromCode(typeCode) {
        if ((typeCode >= 0x01) && (typeCode <= 0x07)) { return "DJI"; }
        if ((typeCode >= 0x10) && (typeCode <= 0x12)) { return "AUTEL"; }
        if (typeCode == 0x20) { return "FPV"; }
        if (typeCode == 0x30) { return "UNKNOWN"; }   // WiFi, deliberately not DJI

        // 0x00 and every unlisted code. Never guessed.
        return "UNKNOWN";
    }

    // The DW01 wire format sends no description text, unlike the TTSKW07, so
    // the model detail is reconstructed from the vendor table. Returns null for
    // an unlisted code: nothing is invented for a code we do not have.
    static function modelTextFromCode(typeCode) {
        if (typeCode == 0x01) { return "DJI LB(Phantom 3A/3P/4/4A/4P, Inspire 1/2, Matrice M200)"; }
        if (typeCode == 0x02) { return "DJI OCU(Mavic/PRO, P4P V2.0, Mavic 2/2PRO, Air 2, Mini 3, M30)"; }
        if (typeCode == 0x03) { return "DJI Special(Phantom 4 RTK)"; }
        if (typeCode == 0x04) { return "DJI Special(MINI 2)"; }
        if (typeCode == 0x05) { return "DJI O3+(Mavic 3 series, AVATA)"; }
        if (typeCode == 0x06) { return "DJI O3(DJI FPV, Mavic Air 2S, Mini 3 Pro)"; }
        if (typeCode == 0x07) { return "DJI O4(O4 video transmission)"; }
        if (typeCode == 0x10) { return "AUTEL SkyLink(EVO 2)"; }
        if (typeCode == 0x11) { return "AUTEL SkyLink(LITE/NANO)"; }
        if (typeCode == 0x12) { return "AUTEL SkyLink(EVO 2 PRO)"; }
        if (typeCode == 0x20) { return "FM Analog(DIY FPV, Aircraft model)"; }
        if (typeCode == 0x30) { return "WiFi(Phantom 3S, SPARK, Tello, PARROT series)"; }
        if (typeCode == 0x00) { return "Unrecognized"; }
        return null;
    }

    // ---- normalization -----------------------------------------------------
    //
    // Ranges are deliberately a little wider than the nominal allocations so a
    // real detection at a band edge is not thrown away, but they are still
    // bounded: a frequency outside all of them degrades to UNKNOWN rather than
    // snapping to the nearest band. The DW01 sweeps 0-8000MHz, so out-of-band
    // values are ordinary traffic, not errors.
    static function bandFromFrequency(megahertz) {
        if ((megahertz >= 1100) && (megahertz <= 1350)) { return "1.2GHz"; }
        if ((megahertz >= 2350) && (megahertz <= 2550)) { return "2.4GHz"; }
        if ((megahertz >= 3200) && (megahertz <= 3600)) { return "3.3GHz"; }
        if ((megahertz >= 5650) && (megahertz <= 5950)) { return "5.8GHz"; }
        return "UNKNOWN";
    }

    static function distanceFromSignal(signalValue) {
        if (signalValue >= DW01_SIGNAL_NEAR_MIN) { return "NEAR"; }
        if (signalValue >= DW01_SIGNAL_MID_MIN) { return "MID"; }
        return "FAR";
    }

    // INVARIANT: never CRITICAL. Nothing in a single detector record justifies
    // the top severity; escalation is the watch's job, based on track
    // persistence a single record does not have.
    static function severityFromDistance(distance) {
        if (distance.equals("NEAR")) { return "HIGH"; }
        if (distance.equals("MID")) { return "MEDIUM"; }
        return "LOW";
    }

    // ---- field readers -----------------------------------------------------

    // Reads at most maxDigits decimal digits from chars[from]. Bounded so a run
    // of digits cannot spill into the next field. Returns null when no digit is
    // present, otherwise { :value, :end }.
    static function readBoundedUnsigned(chars, length, from, maxDigits) {
        var i = from;
        var value = 0;
        var digits = 0;

        while ((i < length) && (digits < maxDigits)) {
            var digit = digitValue(chars[i]);

            if (digit < 0) {
                break;
            }

            value = (value * 10) + digit;
            digits += 1;
            i += 1;
        }

        if (digits == 0) {
            return null;
        }

        return { :value => value, :end => i };
    }

    // Reads EXACTLY two hex characters. Fixed width on purpose: 'C' is a valid
    // hex digit, so a greedy read would swallow the C field that follows.
    static function readHexPair(chars, length, from) {
        if ((from + 2) > length) {
            return null;
        }

        var high = hexValue(chars[from]);
        var low = hexValue(chars[from + 1]);

        if ((high < 0) || (low < 0)) {
            return null;
        }

        return { :value => (high * 16) + low, :end => from + 2 };
    }

    // ---- the parser --------------------------------------------------------

    // Parses one raw DW01 record.
    //
    // timestampMs and sequence are supplied by the caller; the parser reads no
    // clock, so it stays testable and side-effect free -- the same contract as
    // the C++ version.
    //
    // Returns { :result, :alert, :diagnostics }. alert is null unless result is
    // DW01_RESULT_OK.
    static function parseLine(line, timestampMs, sequence) {
        var diagnostics = new DW01Diagnostics();

        if (line == null) {
            return { :result => DW01_RESULT_NOT_A_DETECTION, :alert => null, :diagnostics => diagnostics };
        }

        var chars = line.toCharArray();
        var length = chars.size();

        if ((length == 0) || (length > DW01_MAX_LINE)) {
            return { :result => DW01_RESULT_NOT_A_DETECTION, :alert => null, :diagnostics => diagnostics };
        }

        // Trim whitespace and line endings: a BLE push may arrive padded.
        var begin = 0;

        while ((begin < length) && isTrimmable(chars[begin])) {
            begin += 1;
        }

        while ((length > begin) && isTrimmable(chars[length - 1])) {
            length -= 1;
        }

        if (begin >= length) {
            return { :result => DW01_RESULT_NOT_A_DETECTION, :alert => null, :diagnostics => diagnostics };
        }

        // A record starts at 'F'. Anything else is another device's chatter, a
        // banner or noise: skip quietly rather than reporting an error.
        if (chars[begin] != 'F') {
            return { :result => DW01_RESULT_NOT_A_DETECTION, :alert => null, :diagnostics => diagnostics };
        }

        // F: up to four digits, bounded so it cannot run into the R marker.
        var frequency = readBoundedUnsigned(chars, length, begin + 1, 4);

        if (frequency == null) {
            return { :result => DW01_RESULT_MALFORMED, :alert => null, :diagnostics => diagnostics };
        }

        var cursor = frequency[:end];

        if ((cursor >= length) || (chars[cursor] != 'R')) {
            return { :result => DW01_RESULT_MALFORMED, :alert => null, :diagnostics => diagnostics };
        }

        // R: up to three digits, per the confirmed 0-128 range.
        var signal = readBoundedUnsigned(chars, length, cursor + 1, 3);

        if (signal == null) {
            return { :result => DW01_RESULT_MALFORMED, :alert => null, :diagnostics => diagnostics };
        }

        cursor = signal[:end];

        if ((cursor >= length) || (chars[cursor] != 'T')) {
            return { :result => DW01_RESULT_MALFORMED, :alert => null, :diagnostics => diagnostics };
        }

        // T: EXACTLY two hex digits. See "THE HEX TRAP" above.
        var type = readHexPair(chars, length, cursor + 1);

        if (type == null) {
            return { :result => DW01_RESULT_MALFORMED, :alert => null, :diagnostics => diagnostics };
        }

        cursor = type[:end];

        var frequencyMhz = frequency[:value];
        var signalValue = signal[:value];
        var typeCode = type[:value];

        diagnostics.hasFrequency = true;
        diagnostics.frequencyMhz = frequencyMhz;
        diagnostics.hasSignal = true;
        diagnostics.signalValue = signalValue;
        diagnostics.signalOutOfRange = (signalValue > DW01_SIGNAL_MAX);
        diagnostics.hasTypeCode = true;
        diagnostics.typeCode = typeCode;
        diagnostics.typeCodeRecognized = isKnownTypeCode(typeCode);

        // C: optional and never interpreted. A record without it still parses
        // -- the meaning is unknown, so it cannot be a precondition for a
        // detection.
        if ((cursor < length) && (chars[cursor] == 'C')) {
            diagnostics.hasCField = true;
            diagnostics.cField = trimmedText(chars, cursor + 1, length);
        }

        var threat = threatFromCode(typeCode);
        var band = bandFromFrequency(frequencyMhz);
        var distance = distanceFromSignal(signalValue);

        // PORT NOTE: the C++ parser fills its own Alert struct. Here the shared
        // AlertModel is used, via its existing constructor. AlertModel is NOT
        // modified by this port.
        //
        // confidence is null: the device reports none, and 0 would read as
        // "certainly not a threat" rather than "no data".
        //
        // activeBands is null and hasBandDetail stays false: the DW01 reports
        // one frequency per record, not four band strengths, so there is no
        // per-band detail to claim.
        var alert = new AlertModel(
            threat,
            severityFromDistance(distance),
            null,
            band,
            distance,
            null,
            null,
            "DW01",
            sequence);

        alert.timestampMs = timestampMs;
        alert.sensorType = "RF";

        // The raw code always travels, recognized or not. For an unlisted code
        // it is the only identifier of a new protocol, and it is what makes a
        // field report to the vendor actionable.
        //
        // NOTE: this is the HEX-DECODED value. "T11" becomes 17, where the
        // TTSKW07 reads the same two characters as decimal 11.
        alert.detectorTypeCode = typeCode;

        var modelText = modelTextFromCode(typeCode);

        if (modelText != null) {
            alert.droneClass = modelText;
        } else {
            // PORT NOTE: AlertModel's constructor seeds droneClass with
            // "UNKNOWN", whereas the C++ Alert starts empty. Cleared here so an
            // unlisted code carries no invented text in either implementation.
            alert.droneClass = "";
        }

        // Nothing identifiable and no usable band: a real detection with no
        // usable classification, which is exactly a contact alert.
        if (threat.equals("UNKNOWN") && band.equals("UNKNOWN")) {
            alert.alertKind = "CONTACT";
        } else {
            alert.alertKind = "CLASSIFIED";
        }

        return { :result => DW01_RESULT_OK, :alert => alert, :diagnostics => diagnostics };
    }

    // Copies chars[begin, end) with surrounding whitespace removed.
    //
    // PORT NOTE: the C++ copyTrimmed writes into a fixed buffer and reports
    // truncation. Monkey C strings grow, so there is no capacity to overflow
    // and no truncation flag to set.
    static function trimmedText(chars, begin, end) {
        while ((begin < end) && isTrimmable(chars[begin])) {
            begin += 1;
        }

        while ((end > begin) && isTrimmable(chars[end - 1])) {
            end -= 1;
        }

        var text = "";

        for (var i = begin; i < end; i += 1) {
            text += chars[i].toString();
        }

        return text;
    }
}
