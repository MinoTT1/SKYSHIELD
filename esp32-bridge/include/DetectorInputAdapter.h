#pragma once

#include <Arduino.h>

#include "SkyShieldProtocol.h"

// Bench test-injection adapter: lets an operator type an alert into the serial
// console to drive the HUD without detector hardware.
//
// This is NOT a live detector input. It is renamed and moved behind
// IDetectorAdapter in the detector block; this version only exists to keep the
// tree coherent while the wire format changes.
class DetectorInputAdapter {
public:
    bool readAlert(skyshield::Alert& alert, String& rawPayload, uint32_t timestampMs, uint32_t sequence) {
        rawPayload = "";

        if (!Serial.available()) {
            return false;
        }

        String line = Serial.readStringUntil('\n');
        line.trim();

        if (line.length() == 0) {
            return false;
        }

        if (!parseShortcut(line, alert, timestampMs, sequence)) {
            Serial.print("INVALID SERIAL INJECT INPUT: ");
            Serial.println(line);
            return false;
        }

        rawPayload = line;
        return true;
    }

private:
    bool parseShortcut(const String& line, skyshield::Alert& alert,
                       uint32_t timestampMs, uint32_t sequence) const {
        using namespace skyshield;

        alertInit(alert);
        alert.timestampMs = timestampMs;
        alert.sequence = sequence;
        alert.sensorType = SENSOR_RF;
        alertSetSource(alert, "SERIAL_INJECT");

        if (line.equalsIgnoreCase("FPV")) {
            alert.threat = THREAT_FPV;
            alert.severity = SEVERITY_HIGH;
            alert.band = BAND_5_8;
            alert.distance = DISTANCE_NEAR;
            alert.hasConfidence = true;
            alert.confidence = 87;
            alertSetDroneClass(alert, "FPV");
            return true;
        }

        if (line.equalsIgnoreCase("MAVIC")) {
            alert.threat = THREAT_DJI;
            alert.severity = SEVERITY_MEDIUM;
            alert.band = BAND_2_4;
            alert.distance = DISTANCE_MID;
            alert.hasConfidence = true;
            alert.confidence = 72;
            alertSetDroneClass(alert, "MAVIC");
            return true;
        }

        if (line.equalsIgnoreCase("AUTEL")) {
            alert.threat = THREAT_DJI;
            alert.severity = SEVERITY_MEDIUM;
            alert.band = BAND_2_4;
            alert.distance = DISTANCE_MID;
            alert.hasConfidence = true;
            alert.confidence = 70;
            alertSetDroneClass(alert, "AUTEL");
            return true;
        }

        if (line.equalsIgnoreCase("UNKNOWN")) {
            alert.threat = THREAT_UNKNOWN;
            alert.severity = SEVERITY_CRITICAL;
            alert.band = BAND_MULTI;
            alert.distance = DISTANCE_NEAR;
            alert.hasConfidence = true;
            alert.confidence = 94;
            alertSetDroneClass(alert, "UNKNOWN");
            return true;
        }

        // Data-less contact: exercises the no-classification path on the bench.
        if (line.equalsIgnoreCase("CONTACT")) {
            alertInitContact(alert, timestampMs, sequence);
            alertSetSource(alert, "SERIAL_INJECT");
            return true;
        }

        return false;
    }
};
