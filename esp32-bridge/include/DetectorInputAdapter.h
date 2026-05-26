#pragma once

#include <Arduino.h>

#include "SkyShieldAlert.h"

class DetectorInputAdapter {
public:
    bool readAlert(NormalizedAlert& alert, String& rawDetectorPayload) {
        (void)alert;
        rawDetectorPayload = "";

        // TODO: connect live detector sources here.
        // Planned input paths:
        // - UART serial packets from a detector board
        // - UDP packets from a local RF processor
        // - MQTT messages from a gateway
        // - detector-specific API adapters
        return false;
    }
};
