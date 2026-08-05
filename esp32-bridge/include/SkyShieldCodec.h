#pragma once

// THE SKYSHIELD CBOR codec for the CORE side. One encoder, one decoder.
//
// Arduino-free by design so the contract test in tools/contract-test compiles
// and runs this exact code natively. Do not add <Arduino.h> or String here.
//
// Wire format: docs/wire-protocol.md
//
// Only the CBOR subset documented in that file is supported: unsigned ints,
// text strings, arrays, maps and null. Negative ints, byte strings, tags,
// floats and indefinite-length items are rejected. Keeping the accepted
// surface this narrow limits what a malformed or hostile packet can do.

#include "SkyShieldProtocol.h"

namespace skyshield {

// CBOR major types, shifted into the high 3 bits of the initial byte.
static const uint8_t CBOR_MAJOR_UINT = 0x00;
static const uint8_t CBOR_MAJOR_TSTR = 0x60;
static const uint8_t CBOR_MAJOR_ARRAY = 0x80;
static const uint8_t CBOR_MAJOR_MAP = 0xA0;
static const uint8_t CBOR_NULL = 0xF6;

// ---------------------------------------------------------------------------
// Encoder
// ---------------------------------------------------------------------------

// Bounded output buffer. Every write is capacity-checked; once a write would
// overflow, the writer latches into an overflow state and stays there, so a
// caller that ignores intermediate returns still cannot emit a truncated
// packet -- it gets a hard failure at the end.
class CborWriter {
public:
    CborWriter(uint8_t* buffer, size_t capacity)
        : _buffer(buffer), _capacity(capacity), _length(0), _overflowed(false) {}

    bool overflowed() const { return _overflowed; }
    size_t length() const { return _length; }

    void writeUint(uint64_t value) { writeTypedValue(CBOR_MAJOR_UINT, value); }

    void writeNull() { writeByte(CBOR_NULL); }

    void writeMapHeader(size_t entryCount) {
        writeTypedValue(CBOR_MAJOR_MAP, static_cast<uint64_t>(entryCount));
    }

    void writeArrayHeader(size_t itemCount) {
        writeTypedValue(CBOR_MAJOR_ARRAY, static_cast<uint64_t>(itemCount));
    }

    void writeTextString(const char* text) {
        if (text == nullptr) {
            _overflowed = true;
            return;
        }

        size_t length = 0;
        while (text[length] != '\0') {
            length += 1;
        }

        writeTypedValue(CBOR_MAJOR_TSTR, static_cast<uint64_t>(length));

        for (size_t i = 0; i < length; i += 1) {
            writeByte(static_cast<uint8_t>(text[i]));
        }
    }

private:
    uint8_t* _buffer;
    size_t _capacity;
    size_t _length;
    bool _overflowed;

    void writeByte(uint8_t value) {
        if (_overflowed || (_length >= _capacity)) {
            _overflowed = true;
            return;
        }

        _buffer[_length] = value;
        _length += 1;
    }

    // Canonical CBOR: always use the shortest form that fits the value.
    void writeTypedValue(uint8_t majorType, uint64_t value) {
        if (value < 24) {
            writeByte(majorType | static_cast<uint8_t>(value));
        } else if (value <= 0xFF) {
            writeByte(majorType | 24);
            writeByte(static_cast<uint8_t>(value));
        } else if (value <= 0xFFFF) {
            writeByte(majorType | 25);
            writeByte(static_cast<uint8_t>(value >> 8));
            writeByte(static_cast<uint8_t>(value));
        } else if (value <= 0xFFFFFFFFULL) {
            writeByte(majorType | 26);
            writeByte(static_cast<uint8_t>(value >> 24));
            writeByte(static_cast<uint8_t>(value >> 16));
            writeByte(static_cast<uint8_t>(value >> 8));
            writeByte(static_cast<uint8_t>(value));
        } else {
            writeByte(majorType | 27);
            for (int shift = 56; shift >= 0; shift -= 8) {
                writeByte(static_cast<uint8_t>(value >> shift));
            }
        }
    }
};

// Encodes an alert into buffer. Returns the number of bytes written, or 0 on
// failure (buffer too small, or result exceeds MAX_PAYLOAD_BYTES).
//
// Never emits a partial packet: on any overflow the result is 0 and the caller
// must not transmit.
inline size_t encodeAlert(const Alert& alert, uint8_t* buffer, size_t capacity) {
    if ((buffer == nullptr) || (capacity == 0)) {
        return 0;
    }

    size_t entryCount = 10;  // the ten required fields

    if (alert.hasDroneClass) { entryCount += 1; }
    if (alert.hasDetectorLatency) { entryCount += 1; }
    if (alert.hasBands) { entryCount += 1; }
    if (alert.hasDirection) { entryCount += 1; }
    if (alert.hasSource) { entryCount += 1; }
    if (alert.hasDetectorTypeCode) { entryCount += 1; }

    CborWriter writer(buffer, capacity);

    writer.writeMapHeader(entryCount);

    writer.writeUint(KEY_PROTOCOL_VERSION);
    writer.writeUint(PROTOCOL_VERSION);

    writer.writeUint(KEY_TIMESTAMP_MS);
    writer.writeUint(alert.timestampMs);

    writer.writeUint(KEY_SEQUENCE);
    writer.writeUint(alert.sequence);

    writer.writeUint(KEY_SENSOR_TYPE);
    writer.writeUint(alert.sensorType);

    writer.writeUint(KEY_ALERT_KIND);
    writer.writeUint(alert.alertKind);

    writer.writeUint(KEY_THREAT);
    writer.writeUint(alert.threat);

    writer.writeUint(KEY_SEVERITY);
    writer.writeUint(alert.severity);

    writer.writeUint(KEY_BAND);
    writer.writeUint(alert.band);

    writer.writeUint(KEY_DISTANCE);
    writer.writeUint(alert.distance);

    // null rather than 0 when the detector reported no confidence.
    writer.writeUint(KEY_CONFIDENCE);
    if (alert.hasConfidence) {
        writer.writeUint(alert.confidence);
    } else {
        writer.writeNull();
    }

    if (alert.hasDroneClass) {
        writer.writeUint(KEY_DRONE_CLASS);
        writer.writeTextString(alert.droneClass);
    }

    if (alert.hasDetectorLatency) {
        writer.writeUint(KEY_DETECTOR_LATENCY_MS);
        writer.writeUint(alert.detectorLatencyMs);
    }

    if (alert.hasBands) {
        writer.writeUint(KEY_BANDS);
        writer.writeArrayHeader(4);
        for (size_t i = 0; i < 4; i += 1) {
            writer.writeUint(alert.bands[i]);
        }
    }

    if (alert.hasDirection) {
        writer.writeUint(KEY_DIRECTION);
        writer.writeUint(alert.direction);
    }

    if (alert.hasSource) {
        writer.writeUint(KEY_SOURCE);
        writer.writeTextString(alert.source);
    }

    if (alert.hasDetectorTypeCode) {
        writer.writeUint(KEY_DETECTOR_TYPE_CODE);
        writer.writeUint(alert.detectorTypeCode);
    }

    if (writer.overflowed()) {
        return 0;
    }

    if (writer.length() > MAX_PAYLOAD_BYTES) {
        return 0;
    }

    return writer.length();
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

class CborReader {
public:
    CborReader(const uint8_t* buffer, size_t length)
        : _buffer(buffer), _length(length), _offset(0) {}

    bool exhausted() const { return _offset >= _length; }
    size_t offset() const { return _offset; }

    bool readInitialByte(uint8_t& majorType, uint8_t& additional) {
        if (_offset >= _length) {
            return false;
        }

        const uint8_t initial = _buffer[_offset];
        _offset += 1;
        majorType = initial & 0xE0;
        additional = initial & 0x1F;
        return true;
    }

    // Reads the argument that follows an initial byte. Rejects indefinite
    // length (31) and the reserved encodings 28-30.
    bool readArgument(uint8_t additional, uint64_t& value) {
        if (additional < 24) {
            value = additional;
            return true;
        }

        size_t byteCount = 0;

        switch (additional) {
            case 24: byteCount = 1; break;
            case 25: byteCount = 2; break;
            case 26: byteCount = 4; break;
            case 27: byteCount = 8; break;
            default: return false;  // 28-30 reserved, 31 indefinite
        }

        if ((_offset + byteCount) > _length) {
            return false;
        }

        value = 0;
        for (size_t i = 0; i < byteCount; i += 1) {
            value = (value << 8) | _buffer[_offset];
            _offset += 1;
        }

        return true;
    }

    bool readUint(uint64_t& value) {
        uint8_t majorType = 0;
        uint8_t additional = 0;

        if (!readInitialByte(majorType, additional)) {
            return false;
        }

        if (majorType != CBOR_MAJOR_UINT) {
            return false;
        }

        return readArgument(additional, value);
    }

    bool copyTextString(uint64_t length, char* out, size_t capacity) {
        if (length >= capacity) {
            return false;
        }

        if ((_offset + length) > _length) {
            return false;
        }

        for (uint64_t i = 0; i < length; i += 1) {
            out[i] = static_cast<char>(_buffer[_offset]);
            _offset += 1;
        }

        out[length] = '\0';
        return true;
    }

    // Steps over one complete item of any supported type. Used to tolerate
    // unknown keys from a newer minor revision without losing framing.
    bool skipItem(int depth = 0) {
        if (depth > 4) {
            return false;
        }

        uint8_t majorType = 0;
        uint8_t additional = 0;

        if (!readInitialByte(majorType, additional)) {
            return false;
        }

        if ((majorType == 0xE0) && (additional == 22)) {
            return true;  // null
        }

        uint64_t value = 0;

        if (!readArgument(additional, value)) {
            return false;
        }

        if (majorType == CBOR_MAJOR_UINT) {
            return true;
        }

        if (majorType == CBOR_MAJOR_TSTR) {
            if ((_offset + value) > _length) {
                return false;
            }
            _offset += value;
            return true;
        }

        if (majorType == CBOR_MAJOR_ARRAY) {
            for (uint64_t i = 0; i < value; i += 1) {
                if (!skipItem(depth + 1)) {
                    return false;
                }
            }
            return true;
        }

        if (majorType == CBOR_MAJOR_MAP) {
            for (uint64_t i = 0; i < (value * 2); i += 1) {
                if (!skipItem(depth + 1)) {
                    return false;
                }
            }
            return true;
        }

        return false;
    }

private:
    const uint8_t* _buffer;
    size_t _length;
    size_t _offset;
};

enum DecodeResult : uint8_t {
    DECODE_OK = 0,
    DECODE_MALFORMED = 1,
    DECODE_WRONG_VERSION = 2,
    DECODE_MISSING_FIELD = 3,
    DECODE_BAD_VALUE = 4
};

inline const char* decodeResultName(DecodeResult result) {
    switch (result) {
        case DECODE_OK: return "OK";
        case DECODE_WRONG_VERSION: return "WRONG_VERSION";
        case DECODE_MISSING_FIELD: return "MISSING_FIELD";
        case DECODE_BAD_VALUE: return "BAD_VALUE";
        default: return "MALFORMED";
    }
}

// Decodes a CBOR alert packet. Validates protocol_version, enum ranges and
// presence of every required field. A packet that fails any check is rejected
// outright -- the decoder never guesses a value, because a guessed threat or
// severity on a safety-adjacent HUD is worse than showing nothing.
inline DecodeResult decodeAlert(const uint8_t* buffer, size_t length, Alert& alert) {
    alertInit(alert);

    if ((buffer == nullptr) || (length == 0)) {
        return DECODE_MALFORMED;
    }

    CborReader reader(buffer, length);

    uint8_t majorType = 0;
    uint8_t additional = 0;

    if (!reader.readInitialByte(majorType, additional)) {
        return DECODE_MALFORMED;
    }

    if (majorType != CBOR_MAJOR_MAP) {
        return DECODE_MALFORMED;
    }

    uint64_t entryCount = 0;

    if (!reader.readArgument(additional, entryCount)) {
        return DECODE_MALFORMED;
    }

    bool sawVersion = false;
    bool sawTimestamp = false;
    bool sawSequence = false;
    bool sawSensorType = false;
    bool sawAlertKind = false;
    bool sawThreat = false;
    bool sawSeverity = false;
    bool sawBand = false;
    bool sawDistance = false;
    bool sawConfidence = false;

    for (uint64_t entry = 0; entry < entryCount; entry += 1) {
        uint64_t key = 0;

        if (!reader.readUint(key)) {
            return DECODE_MALFORMED;
        }

        switch (key) {
            case KEY_PROTOCOL_VERSION: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value != PROTOCOL_VERSION) { return DECODE_WRONG_VERSION; }
                sawVersion = true;
                break;
            }

            case KEY_TIMESTAMP_MS: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > 0xFFFFFFFFULL) { return DECODE_BAD_VALUE; }
                alert.timestampMs = static_cast<uint32_t>(value);
                sawTimestamp = true;
                break;
            }

            case KEY_SEQUENCE: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > 0xFFFFFFFFULL) { return DECODE_BAD_VALUE; }
                alert.sequence = static_cast<uint32_t>(value);
                sawSequence = true;
                break;
            }

            case KEY_SENSOR_TYPE: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > SENSOR_CONTACT) { return DECODE_BAD_VALUE; }
                alert.sensorType = static_cast<SensorType>(value);
                sawSensorType = true;
                break;
            }

            case KEY_ALERT_KIND: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > KIND_CONTACT) { return DECODE_BAD_VALUE; }
                alert.alertKind = static_cast<AlertKind>(value);
                sawAlertKind = true;
                break;
            }

            case KEY_THREAT: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > THREAT_AUTEL) { return DECODE_BAD_VALUE; }
                alert.threat = static_cast<Threat>(value);
                sawThreat = true;
                break;
            }

            case KEY_SEVERITY: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > SEVERITY_CRITICAL) { return DECODE_BAD_VALUE; }
                alert.severity = static_cast<Severity>(value);
                sawSeverity = true;
                break;
            }

            case KEY_BAND: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > BAND_MULTI) { return DECODE_BAD_VALUE; }
                alert.band = static_cast<Band>(value);
                sawBand = true;
                break;
            }

            case KEY_DISTANCE: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > DISTANCE_NEAR) { return DECODE_BAD_VALUE; }
                alert.distance = static_cast<Distance>(value);
                sawDistance = true;
                break;
            }

            case KEY_CONFIDENCE: {
                uint8_t confMajor = 0;
                uint8_t confAdditional = 0;

                if (!reader.readInitialByte(confMajor, confAdditional)) {
                    return DECODE_MALFORMED;
                }

                if ((confMajor == 0xE0) && (confAdditional == 22)) {
                    alert.hasConfidence = false;  // explicit null
                    sawConfidence = true;
                    break;
                }

                if (confMajor != CBOR_MAJOR_UINT) {
                    return DECODE_MALFORMED;
                }

                uint64_t value = 0;
                if (!reader.readArgument(confAdditional, value)) {
                    return DECODE_MALFORMED;
                }
                if (value > 100) { return DECODE_BAD_VALUE; }

                alert.hasConfidence = true;
                alert.confidence = static_cast<uint8_t>(value);
                sawConfidence = true;
                break;
            }

            case KEY_DRONE_CLASS: {
                uint8_t strMajor = 0;
                uint8_t strAdditional = 0;

                if (!reader.readInitialByte(strMajor, strAdditional)) {
                    return DECODE_MALFORMED;
                }
                if (strMajor != CBOR_MAJOR_TSTR) { return DECODE_MALFORMED; }

                uint64_t strLength = 0;
                if (!reader.readArgument(strAdditional, strLength)) {
                    return DECODE_MALFORMED;
                }
                if (!reader.copyTextString(strLength, alert.droneClass, DRONE_CLASS_CAPACITY)) {
                    return DECODE_BAD_VALUE;
                }

                alert.hasDroneClass = (alert.droneClass[0] != '\0');
                break;
            }

            case KEY_DETECTOR_LATENCY_MS: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > 0xFFFFFFFFULL) { return DECODE_BAD_VALUE; }
                alert.hasDetectorLatency = true;
                alert.detectorLatencyMs = static_cast<uint32_t>(value);
                break;
            }

            case KEY_BANDS: {
                uint8_t arrayMajor = 0;
                uint8_t arrayAdditional = 0;

                if (!reader.readInitialByte(arrayMajor, arrayAdditional)) {
                    return DECODE_MALFORMED;
                }
                if (arrayMajor != CBOR_MAJOR_ARRAY) { return DECODE_MALFORMED; }

                uint64_t itemCount = 0;
                if (!reader.readArgument(arrayAdditional, itemCount)) {
                    return DECODE_MALFORMED;
                }
                if (itemCount != 4) { return DECODE_BAD_VALUE; }

                for (size_t i = 0; i < 4; i += 1) {
                    uint64_t value = 0;
                    if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                    if (value > STRENGTH_HIGH) { return DECODE_BAD_VALUE; }
                    alert.bands[i] = static_cast<BandStrength>(value);
                }

                alert.hasBands = true;
                break;
            }

            case KEY_DIRECTION: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > DIRECTION_REAR) { return DECODE_BAD_VALUE; }
                alert.hasDirection = true;
                alert.direction = static_cast<Direction>(value);
                break;
            }

            case KEY_SOURCE: {
                uint8_t strMajor = 0;
                uint8_t strAdditional = 0;

                if (!reader.readInitialByte(strMajor, strAdditional)) {
                    return DECODE_MALFORMED;
                }
                if (strMajor != CBOR_MAJOR_TSTR) { return DECODE_MALFORMED; }

                uint64_t strLength = 0;
                if (!reader.readArgument(strAdditional, strLength)) {
                    return DECODE_MALFORMED;
                }
                if (!reader.copyTextString(strLength, alert.source, SOURCE_CAPACITY)) {
                    return DECODE_BAD_VALUE;
                }

                alert.hasSource = (alert.source[0] != '\0');
                break;
            }

            case KEY_DETECTOR_TYPE_CODE: {
                uint64_t value = 0;
                if (!reader.readUint(value)) { return DECODE_MALFORMED; }
                if (value > 0xFFFFu) { return DECODE_BAD_VALUE; }
                alert.hasDetectorTypeCode = true;
                alert.detectorTypeCode = static_cast<uint16_t>(value);
                break;
            }

            default: {
                // Unknown key from a newer minor revision: skip its value and
                // keep framing rather than failing the whole packet.
                if (!reader.skipItem()) {
                    return DECODE_MALFORMED;
                }
                break;
            }
        }
    }

    if (!sawVersion) {
        return DECODE_WRONG_VERSION;
    }

    if (!sawTimestamp || !sawSequence || !sawSensorType || !sawAlertKind ||
        !sawThreat || !sawSeverity || !sawBand || !sawDistance || !sawConfidence) {
        return DECODE_MISSING_FIELD;
    }

    return DECODE_OK;
}

}  // namespace skyshield
