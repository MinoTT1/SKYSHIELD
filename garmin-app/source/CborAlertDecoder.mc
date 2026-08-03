import Toybox.System;

// THE SKYSHIELD alert decoder for the watch. There is exactly one.
//
// Mirrors esp32-bridge/include/SkyShieldCodec.h field for field and is verified
// against the same golden vectors by tools/contract-test. Adding a second
// decoder is what caused the protocol drift this replaces -- don't.
//
// Wire format: docs/wire-protocol.md

const SKYSHIELD_PROTOCOL_VERSION = 3;

// CBOR major types, in the high 3 bits of the initial byte.
const CBOR_MAJOR_UINT = 0x00;
const CBOR_MAJOR_TSTR = 0x60;
const CBOR_MAJOR_ARRAY = 0x80;
const CBOR_MAJOR_MAP = 0xA0;
const CBOR_MAJOR_SIMPLE = 0xE0;
const CBOR_SIMPLE_NULL = 22;

// Map keys. Permanent; see docs/wire-protocol.md.
const CBOR_KEY_PROTOCOL_VERSION = 1;
const CBOR_KEY_TIMESTAMP_MS = 2;
const CBOR_KEY_SEQUENCE = 3;
const CBOR_KEY_SENSOR_TYPE = 4;
const CBOR_KEY_ALERT_KIND = 5;
const CBOR_KEY_THREAT = 6;
const CBOR_KEY_SEVERITY = 7;
const CBOR_KEY_BAND = 8;
const CBOR_KEY_DISTANCE = 9;
const CBOR_KEY_CONFIDENCE = 10;
const CBOR_KEY_DRONE_CLASS = 11;
const CBOR_KEY_DETECTOR_LATENCY_MS = 12;
const CBOR_KEY_BANDS = 13;
const CBOR_KEY_DIRECTION = 14;
const CBOR_KEY_SOURCE = 15;

const DECODE_OK = "OK";
const DECODE_MALFORMED = "MALFORMED";
const DECODE_WRONG_VERSION = "WRONG_VERSION";
const DECODE_MISSING_FIELD = "MISSING_FIELD";
const DECODE_BAD_VALUE = "BAD_VALUE";

// Result of a decode attempt. Carries either a populated AlertModel or the
// reason it was rejected, so the HUD can distinguish "no packet yet" from
// "packet arrived and was garbage".
class CborDecodeResult {
    var status;
    var alert;

    function initialize(statusValue, alertValue) {
        status = statusValue;
        alert = alertValue;
    }

    function isOk() {
        return status.equals(DECODE_OK);
    }
}

class CborAlertDecoder {
    var _bytes;
    var _offset;
    var _length;

    function initialize() {
        _bytes = null;
        _offset = 0;
        _length = 0;
    }

    // Decodes a notification payload into an AlertModel.
    //
    // Every field is validated. A packet that fails any check is rejected
    // outright; the decoder never substitutes a guessed value, because a
    // guessed threat or severity on this HUD is worse than showing nothing.
    function decode(bytes) {
        if (bytes == null) {
            return reject(DECODE_MALFORMED, "null payload");
        }

        _bytes = bytes;
        _offset = 0;
        _length = bytes.size();

        if (_length == 0) {
            return reject(DECODE_MALFORMED, "empty payload");
        }

        var header = readInitialByte();

        if (header == null) {
            return reject(DECODE_MALFORMED, "no map header");
        }

        if (header[:major] != CBOR_MAJOR_MAP) {
            return reject(DECODE_MALFORMED, "top level is not a map");
        }

        var entryCount = readArgument(header[:additional]);

        if (entryCount == null) {
            return reject(DECODE_MALFORMED, "bad map length");
        }

        var state = {
            :version => null,
            :timestampMs => null,
            :sequence => null,
            :sensorType => null,
            :alertKind => null,
            :threat => null,
            :severity => null,
            :band => null,
            :distance => null,
            :sawConfidence => false,
            :confidence => null,
            :droneClass => null,
            :detectorLatencyMs => null,
            :bands => null,
            :direction => null,
            :source => null
        };

        for (var entry = 0; entry < entryCount; entry += 1) {
            var key = readUint();

            if (key == null) {
                return reject(DECODE_MALFORMED, "bad key at entry " + entry);
            }

            var failure = readValueForKey(key, state);

            if (failure != null) {
                return failure;
            }
        }

        return buildResult(state);
    }

    // Dispatches one key/value pair into state. Returns null on success or a
    // CborDecodeResult describing the rejection.
    function readValueForKey(key, state) {
        if (key == CBOR_KEY_PROTOCOL_VERSION) {
            var value = readUint();
            if (value == null) { return reject(DECODE_MALFORMED, "bad protocol_version"); }
            if (value != SKYSHIELD_PROTOCOL_VERSION) {
                return reject(DECODE_WRONG_VERSION, "protocol_version=" + value);
            }
            state[:version] = value;
            return null;
        }

        if (key == CBOR_KEY_TIMESTAMP_MS) {
            var value = readUint();
            if (value == null) { return reject(DECODE_MALFORMED, "bad timestamp_ms"); }
            state[:timestampMs] = value;
            return null;
        }

        if (key == CBOR_KEY_SEQUENCE) {
            var value = readUint();
            if (value == null) { return reject(DECODE_MALFORMED, "bad sequence"); }
            state[:sequence] = value;
            return null;
        }

        if (key == CBOR_KEY_SENSOR_TYPE) {
            var value = readBoundedUint(3);
            if (value == null) { return reject(DECODE_BAD_VALUE, "sensor_type"); }
            state[:sensorType] = value;
            return null;
        }

        if (key == CBOR_KEY_ALERT_KIND) {
            var value = readBoundedUint(1);
            if (value == null) { return reject(DECODE_BAD_VALUE, "alert_kind"); }
            state[:alertKind] = value;
            return null;
        }

        if (key == CBOR_KEY_THREAT) {
            var value = readBoundedUint(2);
            if (value == null) { return reject(DECODE_BAD_VALUE, "threat"); }
            state[:threat] = value;
            return null;
        }

        if (key == CBOR_KEY_SEVERITY) {
            var value = readBoundedUint(3);
            if (value == null) { return reject(DECODE_BAD_VALUE, "severity"); }
            state[:severity] = value;
            return null;
        }

        if (key == CBOR_KEY_BAND) {
            var value = readBoundedUint(5);
            if (value == null) { return reject(DECODE_BAD_VALUE, "band"); }
            state[:band] = value;
            return null;
        }

        if (key == CBOR_KEY_DISTANCE) {
            var value = readBoundedUint(3);
            if (value == null) { return reject(DECODE_BAD_VALUE, "distance"); }
            state[:distance] = value;
            return null;
        }

        if (key == CBOR_KEY_CONFIDENCE) {
            return readConfidence(state);
        }

        if (key == CBOR_KEY_DRONE_CLASS) {
            var text = readTextString();
            if (text == null) { return reject(DECODE_MALFORMED, "bad drone_class"); }
            state[:droneClass] = text;
            return null;
        }

        if (key == CBOR_KEY_DETECTOR_LATENCY_MS) {
            var value = readUint();
            if (value == null) { return reject(DECODE_MALFORMED, "bad detector_latency_ms"); }
            state[:detectorLatencyMs] = value;
            return null;
        }

        if (key == CBOR_KEY_BANDS) {
            return readBands(state);
        }

        if (key == CBOR_KEY_DIRECTION) {
            var value = readBoundedUint(3);
            if (value == null) { return reject(DECODE_BAD_VALUE, "direction"); }
            state[:direction] = value;
            return null;
        }

        if (key == CBOR_KEY_SOURCE) {
            var text = readTextString();
            if (text == null) { return reject(DECODE_MALFORMED, "bad source"); }
            state[:source] = text;
            return null;
        }

        // Unknown key from a newer minor revision: skip its value so framing
        // survives rather than failing the whole packet.
        if (!skipItem(0)) {
            return reject(DECODE_MALFORMED, "unskippable key " + key);
        }

        return null;
    }

    // confidence is the one nullable field: CBOR null means the detector
    // reported no confidence, which is NOT the same as 0%.
    function readConfidence(state) {
        var header = readInitialByte();

        if (header == null) {
            return reject(DECODE_MALFORMED, "bad confidence");
        }

        if ((header[:major] == CBOR_MAJOR_SIMPLE) && (header[:additional] == CBOR_SIMPLE_NULL)) {
            state[:sawConfidence] = true;
            state[:confidence] = null;
            return null;
        }

        if (header[:major] != CBOR_MAJOR_UINT) {
            return reject(DECODE_MALFORMED, "confidence not uint or null");
        }

        var value = readArgument(header[:additional]);

        if ((value == null) || (value > 100)) {
            return reject(DECODE_BAD_VALUE, "confidence out of range");
        }

        state[:sawConfidence] = true;
        state[:confidence] = value;
        return null;
    }

    function readBands(state) {
        var header = readInitialByte();

        if ((header == null) || (header[:major] != CBOR_MAJOR_ARRAY)) {
            return reject(DECODE_MALFORMED, "bands not an array");
        }

        var itemCount = readArgument(header[:additional]);

        if ((itemCount == null) || (itemCount != 4)) {
            return reject(DECODE_BAD_VALUE, "bands length");
        }

        var levels = new [4];

        for (var i = 0; i < 4; i += 1) {
            var value = readBoundedUint(3);

            if (value == null) {
                return reject(DECODE_BAD_VALUE, "band strength");
            }

            levels[i] = value;
        }

        state[:bands] = levels;
        return null;
    }

    function buildResult(state) {
        if (state[:version] == null) {
            return reject(DECODE_WRONG_VERSION, "protocol_version absent");
        }

        if ((state[:timestampMs] == null) || (state[:sequence] == null) ||
            (state[:sensorType] == null) || (state[:alertKind] == null) ||
            (state[:threat] == null) || (state[:severity] == null) ||
            (state[:band] == null) || (state[:distance] == null) ||
            !state[:sawConfidence]) {
            return reject(DECODE_MISSING_FIELD, "required field absent");
        }

        var alert = new AlertModel(
            threatName(state[:threat]),
            severityName(state[:severity]),
            state[:confidence],
            bandName(state[:band]),
            distanceName(state[:distance]),
            bandsToModel(state[:bands]),
            directionName(state[:direction]),
            sourceLabel(state[:source]),
            state[:sequence]
        );

        alert.alertKind = alertKindName(state[:alertKind]);
        alert.sensorType = sensorTypeName(state[:sensorType]);
        alert.timestampMs = state[:timestampMs];
        alert.detectorLatencyMs = state[:detectorLatencyMs];
        alert.hasBandDetail = (state[:bands] != null);

        if (state[:droneClass] != null) {
            alert.droneClass = state[:droneClass];
        }

        return new CborDecodeResult(DECODE_OK, alert);
    }

    // ---- enum mapping. Mirrors SkyShieldProtocol.h. ----

    function threatName(value) {
        if (value == 1) { return "FPV"; }
        if (value == 2) { return "DJI"; }
        return "UNKNOWN";
    }

    function severityName(value) {
        if (value == 1) { return "MEDIUM"; }
        if (value == 2) { return "HIGH"; }
        if (value == 3) { return "CRITICAL"; }
        return "LOW";
    }

    function bandName(value) {
        if (value == 1) { return "1.2GHz"; }
        if (value == 2) { return "2.4GHz"; }
        if (value == 3) { return "3.3GHz"; }
        if (value == 4) { return "5.8GHz"; }
        if (value == 5) { return "MULTI"; }
        return "UNKNOWN";
    }

    function distanceName(value) {
        if (value == 1) { return "FAR"; }
        if (value == 2) { return "MID"; }
        if (value == 3) { return "NEAR"; }
        return "UNKNOWN";
    }

    function alertKindName(value) {
        if (value == 1) { return "CONTACT"; }
        return "CLASSIFIED";
    }

    function sensorTypeName(value) {
        if (value == 1) { return "ACOUSTIC"; }
        if (value == 2) { return "RADAR"; }
        if (value == 3) { return "CONTACT"; }
        return "RF";
    }

    function directionName(value) {
        if (value == null) { return null; }
        if (value == 1) { return "LEFT"; }
        if (value == 2) { return "RIGHT"; }
        if (value == 3) { return "REAR"; }
        return "FRONT";
    }

    function bandStrengthName(value) {
        if (value == 1) { return "LOW"; }
        if (value == 2) { return "MED"; }
        if (value == 3) { return "HIGH"; }
        return "NONE";
    }

    function sourceLabel(value) {
        if (value == null) {
            return "";
        }

        return value;
    }

    // When the bridge omits per-band detail we report UNKNOWN rather than
    // synthesizing levels. The watch must not invent telemetry.
    function bandsToModel(levels) {
        var labels = [ "1.2", "2.4", "3.3", "5.8" ];
        var result = new [4];

        for (var i = 0; i < 4; i += 1) {
            var level = "UNKNOWN";

            if (levels != null) {
                level = bandStrengthName(levels[i]);
            }

            result[i] = { :band => labels[i], :level => level };
        }

        return result;
    }

    // ---- primitive CBOR reads ----

    function readInitialByte() {
        if (_offset >= _length) {
            return null;
        }

        var initial = _bytes[_offset] & 0xFF;
        _offset += 1;

        return { :major => initial & 0xE0, :additional => initial & 0x1F };
    }

    // Reads the argument following an initial byte. Rejects indefinite length
    // (31) and the reserved encodings 28-30.
    function readArgument(additional) {
        if (additional < 24) {
            return additional;
        }

        var byteCount = 0;

        if (additional == 24) { byteCount = 1; }
        else if (additional == 25) { byteCount = 2; }
        else if (additional == 26) { byteCount = 4; }
        else { return null; }

        if ((_offset + byteCount) > _length) {
            return null;
        }

        var value = 0;

        for (var i = 0; i < byteCount; i += 1) {
            value = (value * 256) + (_bytes[_offset] & 0xFF);
            _offset += 1;
        }

        return value;
    }

    function readUint() {
        var header = readInitialByte();

        if ((header == null) || (header[:major] != CBOR_MAJOR_UINT)) {
            return null;
        }

        return readArgument(header[:additional]);
    }

    function readBoundedUint(maxValue) {
        var value = readUint();

        if ((value == null) || (value > maxValue)) {
            return null;
        }

        return value;
    }

    function readTextString() {
        var header = readInitialByte();

        if ((header == null) || (header[:major] != CBOR_MAJOR_TSTR)) {
            return null;
        }

        var length = readArgument(header[:additional]);

        if (length == null) {
            return null;
        }

        if ((_offset + length) > _length) {
            return null;
        }

        var text = "";

        for (var i = 0; i < length; i += 1) {
            text += (_bytes[_offset] & 0xFF).toChar().toString();
            _offset += 1;
        }

        return text;
    }

    // Steps over one complete item of any supported type, so an unknown key
    // does not desynchronize the rest of the map.
    function skipItem(depth) {
        if (depth > 4) {
            return false;
        }

        var header = readInitialByte();

        if (header == null) {
            return false;
        }

        if ((header[:major] == CBOR_MAJOR_SIMPLE) && (header[:additional] == CBOR_SIMPLE_NULL)) {
            return true;
        }

        var value = readArgument(header[:additional]);

        if (value == null) {
            return false;
        }

        if (header[:major] == CBOR_MAJOR_UINT) {
            return true;
        }

        if (header[:major] == CBOR_MAJOR_TSTR) {
            if ((_offset + value) > _length) {
                return false;
            }

            _offset += value;
            return true;
        }

        if (header[:major] == CBOR_MAJOR_ARRAY) {
            for (var i = 0; i < value; i += 1) {
                if (!skipItem(depth + 1)) {
                    return false;
                }
            }

            return true;
        }

        if (header[:major] == CBOR_MAJOR_MAP) {
            for (var i = 0; i < (value * 2); i += 1) {
                if (!skipItem(depth + 1)) {
                    return false;
                }
            }

            return true;
        }

        return false;
    }

    function reject(status, detail) {
        System.println("SKYSHIELD decode reject " + status + ": " + detail);
        return new CborDecodeResult(status, null);
    }
}
