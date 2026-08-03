#!/usr/bin/env python3
"""Independent SKYSHIELD CBOR decoder, used as a cross-check.

The C++ encoder and decoder are a matched pair, so they can agree with each
other while both being wrong about CBOR. This decoder is written straight from
RFC 8949 without reference to the C++ implementation, so if the bridge emits
something that is not real CBOR, this catches it.

It also decodes the golden vectors in the fixture and re-checks the SKYSHIELD
semantics on top, which is what the Garmin decoder has to agree with.

No third-party dependencies on purpose: CI should not need a package index to
verify the wire format.

Usage:
    skyshield_cbor.py <expected_alerts.txt>
    skyshield_cbor.py --decode <hex>
"""

import sys

PROTOCOL_VERSION = 3

KEY_NAMES = {
    1: "protocol_version",
    2: "timestamp_ms",
    3: "sequence",
    4: "sensor_type",
    5: "alert_kind",
    6: "threat",
    7: "severity",
    8: "band",
    9: "distance",
    10: "confidence",
    11: "drone_class",
    12: "detector_latency_ms",
    13: "bands",
    14: "direction",
    15: "source",
}

SENSOR_TYPES = ["rf", "acoustic", "radar", "contact"]
ALERT_KINDS = ["classified", "contact"]
THREATS = ["UNKNOWN", "FPV", "DJI"]
SEVERITIES = ["LOW", "MEDIUM", "HIGH", "CRITICAL"]
BANDS = ["UNKNOWN", "1.2GHz", "2.4GHz", "3.3GHz", "5.8GHz", "MULTI"]
DISTANCES = ["UNKNOWN", "FAR", "MID", "NEAR"]
BAND_STRENGTHS = ["NONE", "LOW", "MED", "HIGH"]
DIRECTIONS = ["FRONT", "LEFT", "RIGHT", "REAR"]


class CborError(Exception):
    pass


class Decoder:
    """Minimal RFC 8949 decoder covering the SKYSHIELD subset."""

    def __init__(self, data):
        self.data = data
        self.offset = 0

    def _read(self, count):
        if self.offset + count > len(self.data):
            raise CborError("read past end of buffer")
        chunk = self.data[self.offset:self.offset + count]
        self.offset += count
        return chunk

    def _header(self):
        initial = self._read(1)[0]
        return initial >> 5, initial & 0x1F

    def _argument(self, additional):
        if additional < 24:
            return additional
        if additional == 24:
            return self._read(1)[0]
        if additional == 25:
            return int.from_bytes(self._read(2), "big")
        if additional == 26:
            return int.from_bytes(self._read(4), "big")
        if additional == 27:
            return int.from_bytes(self._read(8), "big")
        if additional == 31:
            raise CborError("indefinite length is not part of the accepted subset")
        raise CborError("reserved additional information %d" % additional)

    def decode_item(self):
        major, additional = self._header()

        if major == 7:
            if additional == 22:
                return None
            raise CborError("unsupported simple value %d" % additional)

        value = self._argument(additional)

        if major == 0:
            return value
        if major == 3:
            return self._read(value).decode("utf-8")
        if major == 4:
            return [self.decode_item() for _ in range(value)]
        if major == 5:
            result = {}
            for _ in range(value):
                key = self.decode_item()
                result[key] = self.decode_item()
            return result

        raise CborError("major type %d is not part of the accepted subset" % major)

    def decode(self):
        item = self.decode_item()
        if self.offset != len(self.data):
            raise CborError(
                "trailing bytes: consumed %d of %d" % (self.offset, len(self.data))
            )
        return item


def _enum(table, value, label):
    if not isinstance(value, int) or not 0 <= value < len(table):
        raise CborError("%s value %r is out of range" % (label, value))
    return table[value]


def decode_alert(payload):
    """Decodes a SKYSHIELD packet into named fields, validating as it goes."""
    raw = Decoder(payload).decode()

    if not isinstance(raw, dict):
        raise CborError("top level item is not a map")

    version = raw.get(1)
    if version != PROTOCOL_VERSION:
        raise CborError("unsupported protocol_version %r" % (version,))

    required = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    missing = [KEY_NAMES[key] for key in required if key not in raw]
    if missing:
        raise CborError("missing required fields: %s" % ", ".join(missing))

    confidence = raw[10]
    if confidence is not None:
        if not isinstance(confidence, int) or not 0 <= confidence <= 100:
            raise CborError("confidence %r is out of range" % (confidence,))

    alert = {
        "protocol_version": version,
        "timestamp_ms": raw[2],
        "sequence": raw[3],
        "sensor_type": _enum(SENSOR_TYPES, raw[4], "sensor_type"),
        "alert_kind": _enum(ALERT_KINDS, raw[5], "alert_kind"),
        "threat": _enum(THREATS, raw[6], "threat"),
        "severity": _enum(SEVERITIES, raw[7], "severity"),
        "band": _enum(BANDS, raw[8], "band"),
        "distance": _enum(DISTANCES, raw[9], "distance"),
        "confidence": confidence,
    }

    if 11 in raw:
        alert["drone_class"] = raw[11]
    if 12 in raw:
        alert["detector_latency_ms"] = raw[12]
    if 13 in raw:
        levels = raw[13]
        if not isinstance(levels, list) or len(levels) != 4:
            raise CborError("bands must be a 4-element array")
        alert["bands"] = [_enum(BAND_STRENGTHS, item, "band strength") for item in levels]
    if 14 in raw:
        alert["direction"] = _enum(DIRECTIONS, raw[14], "direction")
    if 15 in raw:
        alert["source"] = raw[15]

    return alert


def _check(results, description, expected, actual):
    results.append((description, expected, actual, expected == actual))


def verify_fixture(path):
    """Cross-checks every golden CBOR vector in the fixture."""
    results = []

    with open(path, "r", encoding="utf-8") as handle:
        rows = [
            line.strip()
            for line in handle
            if line.strip() and not line.startswith("#")
        ]

    for row in rows:
        fields = row.split("|")
        if len(fields) < 11:
            results.append((row, "11 fields", "%d fields" % len(fields), False))
            continue

        index, result = fields[0], fields[1]
        if result == "SKIPPED":
            continue

        label = "line %s" % index

        try:
            alert = decode_alert(bytes.fromhex(fields[10]))
        except (CborError, ValueError) as error:
            results.append((label, "decodes", "error: %s" % error, False))
            continue

        _check(results, label + " kind", fields[2], alert["alert_kind"])
        _check(results, label + " threat", fields[3], alert["threat"])
        _check(results, label + " band", fields[4], alert["band"])
        _check(results, label + " distance", fields[5], alert["distance"])
        _check(results, label + " severity", fields[6], alert["severity"])

        confidence = "null" if alert["confidence"] is None else str(alert["confidence"])
        _check(results, label + " confidence", fields[7], confidence)

        _check(results, label + " drone_class", fields[8], alert.get("drone_class", "-"))
        _check(results, label + " source", fields[9], alert.get("source", "-"))

    return results


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--decode":
        try:
            for name, value in decode_alert(bytes.fromhex(sys.argv[2])).items():
                print("%-22s %s" % (name, value))
        except (CborError, ValueError) as error:
            print("decode failed: %s" % error)
            return 1
        return 0

    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    results = verify_fixture(sys.argv[1])
    failures = [item for item in results if not item[3]]

    for description, expected, actual, ok in results:
        if not ok:
            print("  FAIL %s\n        expected: %s\n        actual:   %s"
                  % (description, expected, actual))

    print("\n%d checks, %d failures" % (len(results), len(failures)))

    if failures:
        print("INDEPENDENT CBOR CROSS-CHECK FAILED")
        return 1

    print("INDEPENDENT CBOR CROSS-CHECK PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
