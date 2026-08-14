using Toybox.BluetoothLowEnergy as Ble;
import Toybox.System;
import Toybox.Lang;

// Direct BLE client for the Tatusky DW01 detector -- Architecture A.
//
// ===========================================================================
// DORMANT. NOTHING CALLS THIS. THE ESP32 PATH IS STILL THE ONLY LIVE SOURCE.
// ===========================================================================
// Architecture A is the watch connecting straight to the DW01 with no ESP32
// in the path. It is prepared, not adopted. BleAlertSource remains the active
// source and is untouched by this file.
//
// ===========================================================================
// VENDOR-CONFIRMED BLE PARAMETERS (Kawhi, Tatusky)
// ===========================================================================
//   role            DW01 is the peripheral, the watch is the central
//   service         FFE0
//   characteristic  FFE1, delivered by NOTIFICATION -- pushed, never polled
//   profile         standard BLE-UART style (FFE0/FFE1)
//   payload         ASCII, identical to the wired format: F5788R093T06C202
//
// 115200 8N1 is the DW01's own serial rate. It is informational here: over
// BLE we consume notifications, not a UART, so no baud is configured.
//
// ===========================================================================
// WHAT IS AND IS NOT PROVEN
// ===========================================================================
// PROVEN (simulator): notification bytes -> ASCII -> record framing ->
// DW01Parser -> AlertModel. That glue is unit-tested with injected
// FFE1-style payloads and does not need a radio.
//
// NOT PROVEN -- needs the physical DW01:
//   * that Connect IQ connects to and subscribes on FFE0/FFE1 at all. The
//     profile is standard and well supported, so this is LIKELY fine, but
//     "likely" is not "verified".
//   * connection-loss behaviour. Losing the peer crashes the app on the ESP32
//     path and was never solved. Whether that persists with the DW01 as peer
//     is UNKNOWN. Deliberately no loss handling here -- see the note at
//     handleConnectedStateChanged.
//   * notification rate. The vendor did not state one. The framing buffer and
//     the per-record allocation both depend on it. Measure before tuning.

// The Architecture A gate. OFF: this source cannot start.
//
// As with DW01_PARSER_ENABLED, the real guarantee is that no active code
// references this class. The flag is the second lock, not the only one.
const ARCHITECTURE_A_ENABLED = false;

// 16-bit UUIDs expanded against the Bluetooth SIG base UUID, which is how
// Connect IQ wants them: 0000xxxx-0000-1000-8000-00805F9B34FB.
const DW01_SERVICE_UUID = "0000FFE0-0000-1000-8000-00805F9B34FB";
const DW01_DATA_CHARACTERISTIC_UUID = "0000FFE1-0000-1000-8000-00805F9B34FB";

// Substring matched against the advertised device name, as a fallback when a
// scan result does not carry the service UUID. Empty until the real device's
// advertised name is known -- it is NOT guessed, and matching is by service
// UUID until then.
const DW01_DEVICE_NAME_HINT = "";

// Framing guard. A record is ~16 bytes; this is roughly a dozen of them. If
// the buffer ever reaches this without yielding a record, the stream is not
// what we think it is, so it is dropped rather than grown without bound.
const DW01_RX_BUFFER_LIMIT = 200;

class Dw01BleSource extends AlertSource {
    var _latestAlert;
    var _hasUnreadAlert;
    var _enabled;
    var _delegate;
    var _device;
    var _dataCharacteristic;
    var _serviceUuid;
    var _dataCharacteristicUuid;
    var _cccdUuid;
    var _uptimeMs;
    var _sequence;

    // Partial-record accumulator. See extractRecords().
    var _rxBuffer;

    // Counters, for the hardware bring-up log rather than for logic.
    var _notificationCount;
    var _recordCount;
    var _parsedCount;
    var _malformedCount;
    var _skippedCount;
    var _overflowCount;
    var _lastRawRecord;

    function initialize() {
        AlertSource.initialize();
        _latestAlert = null;
        _hasUnreadAlert = false;
        _enabled = false;
        _delegate = null;
        _device = null;
        _dataCharacteristic = null;
        _serviceUuid = null;
        _dataCharacteristicUuid = null;
        _cccdUuid = null;
        _uptimeMs = 0;
        _sequence = 0;
        _rxBuffer = "";
        _notificationCount = 0;
        _recordCount = 0;
        _parsedCount = 0;
        _malformedCount = 0;
        _skippedCount = 0;
        _overflowCount = 0;
        _lastRawRecord = null;
    }

    // ---- lifecycle ---------------------------------------------------------

    function start() {
        if (!ARCHITECTURE_A_ENABLED) {
            log("start refused: Architecture A is disabled");
            return false;
        }

        _enabled = true;

        try {
            _serviceUuid = Ble.stringToUuid(DW01_SERVICE_UUID);
            _dataCharacteristicUuid = Ble.stringToUuid(DW01_DATA_CHARACTERISTIC_UUID);
            _cccdUuid = Ble.cccdUuid();

            // NOTE for integration: Connect IQ allows ONE BLE delegate per
            // app. Setting this one would displace BleAlertSource's. The two
            // sources are therefore mutually exclusive by construction, which
            // is correct -- Architecture A means the ESP32 is not in the path
            // -- but it does mean they can never run side by side.
            _delegate = new Dw01BleDelegate(self);
            Ble.setDelegate(_delegate);

            registerDw01Profile();
            startScan();
            return true;
        } catch (ex) {
            log("start failed: " + ex);
            return false;
        }
    }

    function stop() {
        _enabled = false;
        _dataCharacteristic = null;
        _rxBuffer = "";
    }

    function tick(elapsedMs) {
        _uptimeMs += elapsedMs;
    }

    // ---- the AlertSource surface -------------------------------------------

    function getNextAlert() {
        if (!_hasUnreadAlert) {
            return null;
        }

        _hasUnreadAlert = false;
        return _latestAlert;
    }

    function getLatestAlert() {
        return _latestAlert;
    }

    function hasLatestAlert() {
        return _latestAlert != null;
    }

    function getLastRawRecord() {
        return _lastRawRecord;
    }

    function getNotificationCount() { return _notificationCount; }
    function getRecordCount() { return _recordCount; }
    function getParsedCount() { return _parsedCount; }
    function getMalformedCount() { return _malformedCount; }
    function getSkippedCount() { return _skippedCount; }
    function getOverflowCount() { return _overflowCount; }

    // ---- BLE setup ---------------------------------------------------------

    function registerDw01Profile() {
        if ((_serviceUuid == null) || (_dataCharacteristicUuid == null) || (_cccdUuid == null)) {
            log("profile registration skipped, UUID unavailable");
            return;
        }

        // FFE1 carries the CCCD because the data arrives by notification. This
        // is the standard BLE-UART shape.
        var profile = {
            :uuid => _serviceUuid,
            :characteristics => [
                {
                    :uuid => _dataCharacteristicUuid,
                    :descriptors => [ _cccdUuid ]
                }
            ]
        };

        try {
            Ble.registerProfile(profile);
            log("FFE0/FFE1 profile registration requested");
        } catch (ex) {
            log("profile registration failed: " + ex);
        }
    }

    function startScan() {
        if (!_enabled) {
            return;
        }

        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
            log("scanning for the DW01");
        } catch (ex) {
            log("scan failed: " + ex);
        }
    }

    // Matches on the advertised FFE0 service.
    //
    // Name matching is available but disabled: DW01_DEVICE_NAME_HINT is empty
    // because the real advertised name is not known yet, and inventing one
    // would mean the client silently fails to match the actual device.
    function isDw01Peripheral(scanResult) {
        if (scanResult == null) {
            return false;
        }

        var services = scanResult.getServiceUuids();

        if (services != null) {
            var service = services.next();

            while (service != null) {
                if (service.equals(_serviceUuid)) {
                    return true;
                }

                service = services.next();
            }
        }

        if (DW01_DEVICE_NAME_HINT.length() > 0) {
            var name = scanResult.getDeviceName();

            if ((name != null) && (name.find(DW01_DEVICE_NAME_HINT) != null)) {
                return true;
            }
        }

        return false;
    }

    // ---- BLE callbacks -----------------------------------------------------

    function handleScanResults(scanResults) {
        if (!_enabled) {
            return;
        }

        var result = scanResults.next();

        while (result != null) {
            if (isDw01Peripheral(result)) {
                log("DW01 peripheral matched on FFE0");

                try {
                    Ble.setScanState(Ble.SCAN_STATE_OFF);
                    _device = Ble.pairDevice(result);
                } catch (ex) {
                    log("connect failed: " + ex);
                }

                return;
            }

            result = scanResults.next();
        }
    }

    function handleConnectedStateChanged(device, state) {
        _device = device;

        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            log("connected, discovering FFE1");
            subscribeToData(device);
            return;
        }

        // DELIBERATELY MINIMAL.
        //
        // Connection-loss handling is out of scope and is NOT attempted here.
        // Losing the peer crashes the app on the ESP32 path, was never solved,
        // and every attempt to work around it destabilised normal operation.
        // Whether the DW01 as peer behaves the same way is an open question for
        // hardware bring-up. Adding speculative recovery now would repeat the
        // mistake of guessing before measuring.
        _dataCharacteristic = null;
        _rxBuffer = "";
        log("disconnected");
    }

    function subscribeToData(device) {
        try {
            var service = device.getService(_serviceUuid);

            if (service == null) {
                log("FFE0 service not found on the peer");
                return;
            }

            _dataCharacteristic = service.getCharacteristic(_dataCharacteristicUuid);

            if (_dataCharacteristic == null) {
                log("FFE1 characteristic not found on the peer");
                return;
            }

            var cccd = _dataCharacteristic.getDescriptor(_cccdUuid);

            if (cccd == null) {
                log("FFE1 has no CCCD, cannot subscribe");
                return;
            }

            cccd.requestWrite([0x01, 0x00]b);
            log("notification subscribe requested on FFE1");
        } catch (ex) {
            log("subscribe failed: " + ex);
        }
    }

    function handleDescriptorWrite(descriptor, status) {
        log("subscribe result status=" + status);
    }

    function handleCharacteristicChanged(characteristic, value) {
        if (!isDataCharacteristic(characteristic)) {
            return;
        }

        onNotificationBytes(value);
    }

    function isDataCharacteristic(characteristic) {
        if (characteristic == null) {
            return false;
        }

        try {
            return characteristic.getUuid().equals(_dataCharacteristicUuid);
        } catch (ex) {
            return false;
        }
    }

    // ---- notification -> records -> alerts ---------------------------------

    // Entry point for one FFE1 notification. Separated from the BLE callback so
    // the whole path below can be unit-tested with injected payloads and no
    // radio -- which is what the simulator tests do.
    function onNotificationBytes(value) {
        _notificationCount += 1;

        var text = bytesToAscii(value);

        if (text == null) {
            return;
        }

        _rxBuffer += text;

        // A stream that never yields a record is not the stream we expect.
        // Drop it rather than growing without bound.
        if (_rxBuffer.length() > DW01_RX_BUFFER_LIMIT) {
            _overflowCount += 1;
            log("rx buffer overflow, discarding " + _rxBuffer.length() + " bytes");
            _rxBuffer = "";
            return;
        }

        var records = extractRecords();

        for (var i = 0; i < records.size(); i += 1) {
            handleRecord(records[i]);
        }
    }

    // Splits the accumulated buffer into complete records and leaves any
    // trailing partial behind.
    //
    // ASSUMPTION, TO CONFIRM ON HARDWARE. A BLE-UART bridge forwards bytes in
    // ~20-byte chunks with no framing of its own, so a chunk boundary need not
    // line up with a record boundary. Two framings are handled without
    // preferring either:
    //
    //   * if the device terminates records (CR and/or LF), split on that
    //   * otherwise split before each subsequent 'F', since every record starts
    //     with one
    //
    // Splitting on 'F' rather than on a fixed 16-byte width is deliberate: the
    // C field's length is not specified by the vendor, so assuming a total
    // record length would be a guess. The final segment is always held back --
    // it may be incomplete, and the next notification will finish it.
    function extractRecords() {
        var records = [];
        var chars = _rxBuffer.toCharArray();
        var segment = "";
        var sawTerminator = false;

        for (var i = 0; i < chars.size(); i += 1) {
            var ch = chars[i];

            if ((ch == '\r') || (ch == '\n')) {
                sawTerminator = true;

                if (segment.length() > 0) {
                    records.add(segment);
                    segment = "";
                }

                continue;
            }

            // Start of the next record while one is already in hand.
            if ((ch == 'F') && (segment.length() > 0) && !sawTerminator) {
                records.add(segment);
                segment = "";
            }

            segment += ch.toString();
        }

        // Whatever is left is either a complete final record whose terminator
        // has not arrived, or a genuine partial. Either way it waits.
        _rxBuffer = segment;

        return records;
    }

    // Runs one record through the parser and publishes the result.
    function handleRecord(record) {
        _recordCount += 1;
        _lastRawRecord = record;

        _sequence += 1;

        var parsed = DW01Parser.parseLine(record, _uptimeMs, _sequence);
        var result = parsed[:result];

        if (result.equals(DW01_RESULT_NOT_A_DETECTION)) {
            // Noise and banners are expected on a UART-style stream. Counted,
            // not logged per record, so a chatty link cannot flood the log.
            _skippedCount += 1;
            _sequence -= 1;
            return false;
        }

        if (!result.equals(DW01_RESULT_OK)) {
            _malformedCount += 1;
            _sequence -= 1;
            log("malformed record: " + record);
            return false;
        }

        _parsedCount += 1;
        _latestAlert = parsed[:alert];
        _hasUnreadAlert = true;

        logDiagnostics(record, parsed[:diagnostics]);

        return true;
    }

    // ByteArray -> ASCII. Bytes outside printable ASCII are dropped rather than
    // turned into replacement characters, so a corrupted chunk degrades to a
    // record the parser will reject instead of a plausible-looking wrong one.
    function bytesToAscii(value) {
        if (value == null) {
            return null;
        }

        var text = "";

        try {
            for (var i = 0; i < value.size(); i += 1) {
                var byte = value[i] & 0xFF;

                if (byte == 0x0D) { text += "\r"; continue; }
                if (byte == 0x0A) { text += "\n"; continue; }

                if ((byte >= 0x20) && (byte <= 0x7E)) {
                    text += byte.toChar().toString();
                }
            }
        } catch (ex) {
            log("byte conversion failed: " + ex);
            return null;
        }

        return text;
    }

    // The raw fields are logged even though AlertModel has no home for some of
    // them. The type code identifies an unlisted protocol worth reporting to
    // the vendor, and the C field is the open question that real traffic is
    // meant to answer.
    function logDiagnostics(record, diagnostics) {
        var text = "DW01 RX \"" + record + "\" T=" + diagnostics.typeCode;

        if (!diagnostics.typeCodeRecognized) {
            text += " (UNLISTED)";
        }

        text += " F=" + diagnostics.frequencyMhz + "MHz R=" + diagnostics.signalValue;

        if (diagnostics.signalOutOfRange) {
            text += " (ABOVE THE STATED 0-128)";
        }

        if (diagnostics.hasCField) {
            text += " C=\"" + diagnostics.cField + "\"";
        } else {
            text += " C=<absent>";
        }

        log(text);
    }

    function log(message) {
        System.println("SKYSHIELD DW01BLE " + message);
    }
}

// Mirrors SkyShieldBleDelegate so the two sources are structurally the same.
// Only one may be installed at a time; see the note in start().
class Dw01BleDelegate extends Ble.BleDelegate {
    var _source;

    function initialize(source) {
        BleDelegate.initialize();
        _source = source;
    }

    function onProfileRegister(uuid, status) {
        System.println("SKYSHIELD DW01BLE profile register status=" + status);
    }

    function onScanStateChange(scanState, status) {
        System.println("SKYSHIELD DW01BLE scan state=" + scanState + " status=" + status);
    }

    function onScanResults(scanResults) {
        _source.handleScanResults(scanResults);
    }

    function onConnectedStateChanged(device, state) {
        _source.handleConnectedStateChanged(device, state);
    }

    function onDescriptorWrite(descriptor, status) {
        _source.handleDescriptorWrite(descriptor, status);
    }

    function onCharacteristicChanged(characteristic, value) {
        _source.handleCharacteristicChanged(characteristic, value);
    }
}
