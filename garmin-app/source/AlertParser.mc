import Toybox.System;

// Parses the canonical SKYSHIELD JSON packet into the Garmin AlertModel.
// BLE integration should feed received UTF-8 JSON payloads into this class.
class AlertParser {
    function initialize() {
    }

    function parse(jsonString) {
        System.println("SKYSHIELD parser raw: " + jsonString);

        var threat = parseThreat(jsonString);
        var severity = parseSeverity(jsonString);
        var band = parseBand(jsonString);
        var distance = parseDistance(jsonString);
        var confidence = parseConfidence(jsonString);
        var bands = parseBands(jsonString);
        var direction = parseDirection(jsonString);
        var source = parseSource(jsonString);
        var sequence = parseSequence(jsonString);

        System.println("SKYSHIELD parser fields: threat=" + threat + " severity=" + severity + " band=" + band + " direction=" + direction + " distance=" + distance + " confidence=" + confidence);

        if (threat == null) {
            return fallbackAlert("invalid or missing threat");
        }

        if (severity == null) {
            return fallbackAlert("invalid or missing severity");
        }

        if (band == null) {
            return fallbackAlert("invalid or missing band");
        }

        if (distance == null) {
            return fallbackAlert("invalid or missing distance");
        }

        if (confidence == null) {
            return fallbackAlert("invalid or missing confidence");
        }

        if (bands == null) {
            return fallbackAlert("invalid bands object");
        }

        System.println("SKYSHIELD parser success");

        return new AlertModel(
            threat,
            severity,
            confidence,
            band,
            distance,
            bands,
            direction,
            source,
            sequence
        );
    }

    function fallbackAlert(reason) {
        System.println("SKYSHIELD parser fallback: " + reason);

        return new AlertModel(
            "UNKNOWN",
            "LOW",
            0,
            "MULTI",
            "FAR",
            defaultBands(),
            null,
            "",
            0
        );
    }

    function parseThreat(jsonString) {
        if (hasToken(jsonString, "\"threat\":\"FPV\"")) {
            return "FPV";
        }

        if (hasToken(jsonString, "\"t\":\"F\"")) {
            return "FPV";
        }

        if (hasToken(jsonString, "\"threat\":\"DJI\"")) {
            return "DJI";
        }

        if (hasToken(jsonString, "\"t\":\"D\"")) {
            return "DJI";
        }

        if (hasToken(jsonString, "\"threat\":\"UNKNOWN\"")) {
            return "UNKNOWN";
        }

        if (hasToken(jsonString, "\"t\":\"U\"")) {
            return "UNKNOWN";
        }

        return null;
    }

    function parseSeverity(jsonString) {
        if (hasToken(jsonString, "\"severity\":\"LOW\"")) {
            return "LOW";
        }

        if (hasToken(jsonString, "\"s\":\"L\"")) {
            return "LOW";
        }

        if (hasToken(jsonString, "\"severity\":\"MEDIUM\"")) {
            return "MEDIUM";
        }

        if (hasToken(jsonString, "\"s\":\"M\"")) {
            return "MEDIUM";
        }

        if (hasToken(jsonString, "\"severity\":\"HIGH\"")) {
            return "HIGH";
        }

        if (hasToken(jsonString, "\"s\":\"H\"")) {
            return "HIGH";
        }

        if (hasToken(jsonString, "\"severity\":\"CRITICAL\"")) {
            return "CRITICAL";
        }

        if (hasToken(jsonString, "\"s\":\"C\"")) {
            return "CRITICAL";
        }

        return null;
    }

    function parseBand(jsonString) {
        if (hasToken(jsonString, "\"band\":\"1.2GHz\"")) {
            return "1.2GHz";
        }

        if (hasToken(jsonString, "\"b\":\"12\"")) {
            return "1.2GHz";
        }

        if (hasToken(jsonString, "\"band\":\"2.4GHz\"")) {
            return "2.4GHz";
        }

        if (hasToken(jsonString, "\"b\":\"24\"")) {
            return "2.4GHz";
        }

        if (hasToken(jsonString, "\"band\":\"3.3GHz\"")) {
            return "3.3GHz";
        }

        if (hasToken(jsonString, "\"b\":\"33\"")) {
            return "3.3GHz";
        }

        if (hasToken(jsonString, "\"band\":\"5.8GHz\"")) {
            return "5.8GHz";
        }

        if (hasToken(jsonString, "\"b\":\"58\"")) {
            return "5.8GHz";
        }

        if (hasToken(jsonString, "\"band\":\"MULTI\"")) {
            return "MULTI";
        }

        if (hasToken(jsonString, "\"b\":\"M\"")) {
            return "MULTI";
        }

        return null;
    }

    function parseDistance(jsonString) {
        if (hasToken(jsonString, "\"distance\":\"FAR\"")) {
            return "FAR";
        }

        if (hasToken(jsonString, "\"r\":\"F\"")) {
            return "FAR";
        }

        if (hasToken(jsonString, "\"distance\":\"MID\"")) {
            return "MID";
        }

        if (hasToken(jsonString, "\"r\":\"M\"")) {
            return "MID";
        }

        if (hasToken(jsonString, "\"distance\":\"NEAR\"")) {
            return "NEAR";
        }

        if (hasToken(jsonString, "\"r\":\"N\"")) {
            return "NEAR";
        }

        return null;
    }

    function parseDirection(jsonString) {
        if (hasToken(jsonString, "\"direction\":\"FRONT\"")) {
            return "FRONT";
        }

        if (hasToken(jsonString, "\"direction\":\"LEFT\"")) {
            return "LEFT";
        }

        if (hasToken(jsonString, "\"direction\":\"RIGHT\"")) {
            return "RIGHT";
        }

        if (hasToken(jsonString, "\"direction\":\"REAR\"")) {
            return "REAR";
        }

        return null;
    }

    function parseConfidence(jsonString) {
        for (var value = 0; value <= 100; value += 1) {
            if (hasToken(jsonString, "\"confidence\":" + value + ",")) {
                return value;
            }

            if (hasToken(jsonString, "\"confidence\":" + value + "}")) {
                return value;
            }

            if (hasToken(jsonString, "\"c\":" + value + ",")) {
                return value;
            }

            if (hasToken(jsonString, "\"c\":" + value + "}")) {
                return value;
            }
        }

        return null;
    }

    function parseBands(jsonString) {
        return [
            { :band => "1.2", :level => parseBandStrength(jsonString, "band_1_2") },
            { :band => "2.4", :level => parseBandStrength(jsonString, "band_2_4") },
            { :band => "3.3", :level => parseBandStrength(jsonString, "band_3_3") },
            { :band => "5.8", :level => parseBandStrength(jsonString, "band_5_8") }
        ];
    }

    function parseBandStrength(jsonString, key) {
        if (hasToken(jsonString, "\"" + key + "\":\"LOW\"")) {
            return "LOW";
        }

        if (hasToken(jsonString, "\"" + key + "\":\"MED\"")) {
            return "MED";
        }

        if (hasToken(jsonString, "\"" + key + "\":\"HIGH\"")) {
            return "HIGH";
        }

        if (hasToken(jsonString, "\"" + key + "\":\"NONE\"")) {
            return "NONE";
        }

        return "NONE";
    }

    function parseSource(jsonString) {
        if (hasToken(jsonString, "\"source\":\"GARMIN_MOCK\"")) {
            return "GARMIN_MOCK";
        }

        if (hasToken(jsonString, "\"source\":\"ESP32_SIM\"")) {
            return "ESP32_SIM";
        }

        return "";
    }

    function parseSequence(jsonString) {
        for (var value = 0; value <= 999; value += 1) {
            if (hasToken(jsonString, "\"sequence\":" + value + "}")) {
                return value;
            }

            if (hasToken(jsonString, "\"sequence\":" + value + ",")) {
                return value;
            }
        }

        return 0;
    }

    function defaultBands() {
        return [
            { :band => "1.2", :level => "NONE" },
            { :band => "2.4", :level => "NONE" },
            { :band => "3.3", :level => "NONE" },
            { :band => "5.8", :level => "NONE" }
        ];
    }

    function hasToken(jsonString, token) {
        var index = jsonString.find(token);
        return (index != null) && (index >= 0);
    }
}
