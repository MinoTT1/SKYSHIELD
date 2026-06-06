#pragma once

#include <Arduino.h>

#include "SkyShieldEvent.h"

class SkydroidParser {
public:
    bool parseLine(const String& line, SkyShieldEvent& outEvent) {
        String trimmed = line;
        trimmed.trim();

        if (trimmed.length() == 0) {
            return false;
        }

        outEvent.rawPayload = trimmed;
        outEvent.detectorSource = "SKYDROID";
        outEvent.sourceDetector = "SKYDROID";

        // TODO: replace placeholder recognition with real S10/S12 output mapping.
        // Expected future fields:
        // - drone type / classification
        // - frequency band / MHz
        // - signal strength
        // - severity mapping
        if (trimmed.startsWith("SKYDROID")) {
            return true;
        }

        return false;
    }
};
