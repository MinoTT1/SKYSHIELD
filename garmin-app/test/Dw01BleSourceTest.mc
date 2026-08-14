import Toybox.Lang;
import Toybox.Test;

// Tests for the DW01 BLE client's parse-and-dispatch glue.
//
// The radio cannot be simulated, so these drive onNotificationBytes() directly
// with FFE1-style ByteArray payloads. That covers everything between "bytes
// arrived" and "an AlertModel is available": ASCII conversion, record framing
// across notification boundaries, parser dispatch, and the counters.
//
// It does NOT cover scanning, connecting, subscribing, or connection loss.
// Those need the physical DW01 -- see docs/dw01-architecture-a.md.

// Test support. A (:test) CLASS is compiled into the unit-test build but is not
// enumerated as a test, unlike a module-level (:test) function.
(:test)
class Dw01BleTestSupport {

    static function newSource() {
        return new Dw01BleSource();
    }

    // Builds a ByteArray from ASCII, the way an FFE1 notification arrives.
    static function bytes(text) {
        var chars = text.toCharArray();
        var out = []b;

        for (var i = 0; i < chars.size(); i += 1) {
            out.add(chars[i].toNumber());
        }

        return out;
    }

    static function push(source, text) {
        source.onNotificationBytes(bytes(text));
    }
}

// ---------------------------------------------------------------------------
// 1. One notification carrying exactly one record
// ---------------------------------------------------------------------------
(:test)
function testDw01BleSingleRecord(logger) {
    DW01TestSupport.dw01ResetCounters();

    var source = Dw01BleTestSupport.newSource();
    Dw01BleTestSupport.push(source, "F5788R093T06C202\r\n");

    DW01TestSupport.dw01CheckEqual(logger, "one notification counted", 1, source.getNotificationCount());
    DW01TestSupport.dw01CheckEqual(logger, "one record extracted", 1, source.getRecordCount());
    DW01TestSupport.dw01CheckEqual(logger, "one record parsed", 1, source.getParsedCount());
    DW01TestSupport.dw01CheckEqual(logger, "no malformed", 0, source.getMalformedCount());

    var alert = source.getLatestAlert();
    DW01TestSupport.dw01CheckTrue(logger, "an alert was produced", alert != null);
    DW01TestSupport.dw01CheckEqual(logger, "threat", "DJI", alert.threatType);
    DW01TestSupport.dw01CheckEqual(logger, "band", "5.8GHz", alert.band);
    DW01TestSupport.dw01CheckEqual(logger, "distance", "NEAR", alert.distanceLabel);
    DW01TestSupport.dw01CheckEqual(logger, "raw code", 6, alert.detectorTypeCode);
    DW01TestSupport.dw01CheckEqual(logger, "source label", "DW01", alert.source);
    DW01TestSupport.dw01CheckEqual(logger, "confidence null", null, alert.confidencePercent);

    // getNextAlert is one-shot, matching BleAlertSource's contract.
    DW01TestSupport.dw01CheckTrue(logger, "first getNextAlert returns it", source.getNextAlert() != null);
    DW01TestSupport.dw01CheckEqual(logger, "second getNextAlert is null", null, source.getNextAlert());

    logger.debug("single record: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 2. A record SPLIT across two notifications
// ---------------------------------------------------------------------------
// The case a naive implementation gets wrong. A BLE-UART bridge forwards
// ~20-byte chunks with no framing, so a record can straddle a boundary.
(:test)
function testDw01BleSplitRecord(logger) {
    DW01TestSupport.dw01ResetCounters();

    var source = Dw01BleTestSupport.newSource();

    Dw01BleTestSupport.push(source, "F5788R093");
    DW01TestSupport.dw01CheckEqual(logger, "partial yields no record", 0, source.getRecordCount());
    DW01TestSupport.dw01CheckEqual(logger, "partial yields no alert", null, source.getLatestAlert());

    Dw01BleTestSupport.push(source, "T06C202\r\n");
    DW01TestSupport.dw01CheckEqual(logger, "completion yields one record", 1, source.getRecordCount());
    DW01TestSupport.dw01CheckEqual(logger, "completion yields one parse", 1, source.getParsedCount());

    var alert = source.getLatestAlert();
    DW01TestSupport.dw01CheckTrue(logger, "reassembled alert exists", alert != null);
    DW01TestSupport.dw01CheckEqual(logger, "reassembled threat", "DJI", alert.threatType);
    DW01TestSupport.dw01CheckEqual(logger, "reassembled raw code", 6, alert.detectorTypeCode);
    DW01TestSupport.dw01CheckEqual(logger, "reassembled record text",
        "F5788R093T06C202", source.getLastRawRecord());

    // Split at every possible offset: no boundary may lose or corrupt a record.
    var record = "F5788R093T06C202\r\n";

    for (var cut = 1; cut < record.length(); cut += 1) {
        var s = Dw01BleTestSupport.newSource();
        Dw01BleTestSupport.push(s, record.substring(0, cut));
        Dw01BleTestSupport.push(s, record.substring(cut, record.length()));

        DW01TestSupport.dw01CheckEqual(logger, "split at " + cut + " parses exactly one",
            1, s.getParsedCount());
        DW01TestSupport.dw01CheckEqual(logger, "split at " + cut + " threat",
            "DJI", s.getLatestAlert().threatType);
    }

    logger.debug("split record: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 3. Several records in one notification
// ---------------------------------------------------------------------------
(:test)
function testDw01BleBatchedRecords(logger) {
    DW01TestSupport.dw01ResetCounters();

    // Terminated framing.
    var terminated = Dw01BleTestSupport.newSource();
    Dw01BleTestSupport.push(terminated,
        "F5788R093T06C202\r\nF2440R088T10C150\r\nF3320R093T20C202\r\n");

    DW01TestSupport.dw01CheckEqual(logger, "three terminated records", 3, terminated.getRecordCount());
    DW01TestSupport.dw01CheckEqual(logger, "three parsed", 3, terminated.getParsedCount());
    DW01TestSupport.dw01CheckEqual(logger, "latest is the last one", "FPV",
        terminated.getLatestAlert().threatType);

    // UNTERMINATED framing: no CR/LF at all, records run together. Split
    // happens on the leading 'F' of each record.
    var runOn = Dw01BleTestSupport.newSource();
    Dw01BleTestSupport.push(runOn, "F5788R093T06C202F2440R088T10C150F3320R093T20C202\r\n");

    DW01TestSupport.dw01CheckEqual(logger, "three run-on records", 3, runOn.getRecordCount());
    DW01TestSupport.dw01CheckEqual(logger, "three run-on parsed", 3, runOn.getParsedCount());
    DW01TestSupport.dw01CheckEqual(logger, "run-on latest is the last", "FPV",
        runOn.getLatestAlert().threatType);

    // AUTEL in the middle of a batch must survive as AUTEL.
    var autel = Dw01BleTestSupport.newSource();
    Dw01BleTestSupport.push(autel, "F5788R093T06C202\r\nF2440R088T10C150\r\n");
    DW01TestSupport.dw01CheckEqual(logger, "batched AUTEL stays AUTEL", "AUTEL",
        autel.getLatestAlert().threatType);
    DW01TestSupport.dw01CheckNotEqual(logger, "batched AUTEL never becomes DJI", "DJI",
        autel.getLatestAlert().threatType);

    logger.debug("batched records: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 4. Junk, noise and hostile payloads must not break the client
// ---------------------------------------------------------------------------
(:test)
function testDw01BleRobustness(logger) {
    DW01TestSupport.dw01ResetCounters();

    // Null and empty payloads.
    var empty = Dw01BleTestSupport.newSource();
    empty.onNotificationBytes(null);
    DW01TestSupport.dw01CheckEqual(logger, "null payload yields no record", 0, empty.getRecordCount());
    DW01TestSupport.dw01CheckEqual(logger, "null payload yields no alert", null, empty.getLatestAlert());

    Dw01BleTestSupport.push(empty, "");
    DW01TestSupport.dw01CheckEqual(logger, "empty payload yields no record", 0, empty.getRecordCount());

    // A banner is skipped, not counted as malformed.
    var banner = Dw01BleTestSupport.newSource();
    Dw01BleTestSupport.push(banner, "DW01 v1.0 ready\r\n");
    DW01TestSupport.dw01CheckEqual(logger, "banner skipped", 1, banner.getSkippedCount());
    DW01TestSupport.dw01CheckEqual(logger, "banner produced no alert", null, banner.getLatestAlert());
    DW01TestSupport.dw01CheckEqual(logger, "banner is not malformed", 0, banner.getMalformedCount());

    // A broken record is counted as malformed and produces no alert.
    var broken = Dw01BleTestSupport.newSource();
    Dw01BleTestSupport.push(broken, "F5788R093TZZC202\r\n");
    DW01TestSupport.dw01CheckEqual(logger, "broken record counted malformed", 1, broken.getMalformedCount());
    DW01TestSupport.dw01CheckEqual(logger, "broken record produced no alert", null, broken.getLatestAlert());

    // Non-printable bytes are dropped, so a corrupted chunk degrades to a
    // rejected record rather than a plausible wrong one.
    var noisy = Dw01BleTestSupport.newSource();
    noisy.onNotificationBytes([0x00, 0x01, 0xFF, 0x7F]b);
    DW01TestSupport.dw01CheckEqual(logger, "control bytes produce no alert", null, noisy.getLatestAlert());

    // A stream that never yields a record must not grow without bound.
    var flood = Dw01BleTestSupport.newSource();

    for (var i = 0; i < 20; i += 1) {
        Dw01BleTestSupport.push(flood, "XXXXXXXXXXXXXXXXXXXX");
    }

    DW01TestSupport.dw01CheckTrue(logger, "runaway buffer is dropped", flood.getOverflowCount() > 0);
    DW01TestSupport.dw01CheckEqual(logger, "runaway buffer produced no alert", null, flood.getLatestAlert());

    // ...and the client still works afterwards.
    Dw01BleTestSupport.push(flood, "F5788R093T06C202\r\n");
    DW01TestSupport.dw01CheckEqual(logger, "recovers after an overflow", "DJI",
        flood.getLatestAlert().threatType);

    logger.debug("robustness: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 5. The whole vendor table, delivered over the BLE path
// ---------------------------------------------------------------------------
// Same expectations as the parser suite, but reached through notification
// bytes rather than by calling the parser directly. Proves the transport does
// not alter classification.
(:test)
function testDw01BleTableOverTheWire(logger) {
    DW01TestSupport.dw01ResetCounters();

    var table = [
        ["F5788R093T01C202", "DJI"],
        ["F5788R093T02C202", "DJI"],
        ["F5788R093T05C202", "DJI"],
        ["F5788R093T06C202", "DJI"],
        ["F5788R093T07C202", "DJI"],
        ["F5788R093T10C202", "AUTEL"],
        ["F5788R093T11C202", "AUTEL"],
        ["F5788R093T12C202", "AUTEL"],
        ["F3320R093T20C202", "FPV"],
        ["F2412R064T30C130", "UNKNOWN"],
        ["F5788R093T00C202", "UNKNOWN"],
        ["F5788R093T99C202", "UNKNOWN"]
    ];

    for (var i = 0; i < table.size(); i += 1) {
        var source = Dw01BleTestSupport.newSource();
        Dw01BleTestSupport.push(source, table[i][0] + "\r\n");

        var alert = source.getLatestAlert();
        var tag = "wire " + table[i][0];

        DW01TestSupport.dw01CheckTrue(logger, tag + " produced an alert", alert != null);

        if (alert == null) {
            continue;
        }

        DW01TestSupport.dw01CheckEqual(logger, tag + " threat", table[i][1], alert.threatType);
        DW01TestSupport.dw01CheckNotEqual(logger, tag + " severity never CRITICAL",
            "CRITICAL", alert.riskLevel);
        DW01TestSupport.dw01CheckEqual(logger, tag + " confidence null", null, alert.confidencePercent);
    }

    logger.debug("table over the wire: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}

// ---------------------------------------------------------------------------
// 6. Architecture A is dormant
// ---------------------------------------------------------------------------
(:test)
function testDw01BleIsDormant(logger) {
    DW01TestSupport.dw01ResetCounters();

    DW01TestSupport.dw01CheckTrue(logger, "ARCHITECTURE_A_ENABLED is OFF",
        ARCHITECTURE_A_ENABLED == false);

    // start() must refuse while the gate is off. This touches no BLE API, so
    // it cannot disturb the active ESP32 source.
    var source = Dw01BleTestSupport.newSource();
    DW01TestSupport.dw01CheckEqual(logger, "start() refuses while disabled", false, source.start());

    DW01TestSupport.dw01CheckEqual(logger, "UUID is the vendor-confirmed FFE0",
        "0000FFE0-0000-1000-8000-00805F9B34FB", DW01_SERVICE_UUID);
    DW01TestSupport.dw01CheckEqual(logger, "UUID is the vendor-confirmed FFE1",
        "0000FFE1-0000-1000-8000-00805F9B34FB", DW01_DATA_CHARACTERISTIC_UUID);

    logger.debug("dormancy: " + dw01Checks + " checks, " + dw01Failures + " failures");
    return dw01Failures == 0;
}
