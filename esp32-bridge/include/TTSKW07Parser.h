#pragma once

#include <Arduino.h>

#include "SkyShieldEvent.h"

class TTSKW07Parser {
public:
    bool parseLine(const String& line, SkyShieldEvent& outEvent) {
        String trimmed = line;
        trimmed.trim();

        if (trimmed.length() == 0) {
            return false;
        }

        outEvent.rawPayload = trimmed;
        outEvent.detectorSource = "TTSKW07";
        outEvent.sourceDetector = "TTSKW07";

        // TODO: replace placeholder recognition with the real TTSKW07 ASCII protocol.
        // Expected future fields:
        // - detection time
        // - drone type / drone classification
        // - frequency band
        // - signal strength / RSSI
        if (trimmed.startsWith("TTSKW07")) {
            return true;
        }

        return false;
    }
};
