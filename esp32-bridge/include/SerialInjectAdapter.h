#pragma once

#include <Arduino.h>

#include "IDetectorAdapter.h"
#include "RawSerialCapture.h"
#include "TTSKW07Parser.h"

// Bench test-injection source. An operator types an alert into the USB serial
// console and the bridge emits it.
//
// THIS IS NOT A DETECTOR. It was previously called DetectorInputAdapter and
// the firmware announced it as "LIVE mode", which implied it consumed real
// sensor data when it only ever re-parsed SKYSHIELD's own notation typed by a
// human (audit Finding C-1). The name and the log strings now say what it is.
//
// Two input styles are accepted:
//   1. shortcuts: FPV, MAVIC, AUTEL, UNKNOWN, CONTACT
//   2. a full TTSKW07 line, parsed by the real TTSKW07 parser, so captured
//      detector output can be replayed over USB without the hardware present
class SerialInjectAdapter : public IDetectorAdapter {
public:
    SerialInjectAdapter() : _ready(false) {}

    const char* name() const override { return "SERIAL_INJECT"; }

    bool begin() override {
        _capture.begin(&Serial);
        _ready = true;

        Serial.println("SERIAL_INJECT ready. Type FPV, MAVIC, AUTEL, UNKNOWN, CONTACT,");
        Serial.println("or paste a raw TTSKW07 line to replay it through the real parser.");

        return true;
    }

    void end() override {
        _capture.clear();
        _ready = false;
    }

    bool isReady() const override { return _ready; }

    // Non-blocking, unlike the Serial.readStringUntil it replaces, which could
    // stall the whole firmware loop for up to a second on a partial line and
    // take BLE housekeeping down with it (audit Finding B-4).
    bool poll(uint32_t sequence, skyshield::Alert& alert) override {
        if (!_ready) {
            return false;
        }

        _capture.poll();

        if (!_capture.hasLine()) {
            return false;
        }

        const uint32_t ingestMs = millis();
        const char* line = _capture.getLine();

        if (!buildAlert(line, ingestMs, sequence, alert)) {
            Serial.print("SERIAL_INJECT unrecognized input: ");
            Serial.println(line);
            return false;
        }

        Serial.print("SERIAL_INJECT input: ");
        Serial.println(line);

        const uint32_t processedMs = millis();
        alert.timestampMs = processedMs;
        alert.hasDetectorLatency = true;
        alert.detectorLatencyMs = processedMs - ingestMs;

        return true;
    }

private:
    bool _ready;
    RawSerialCapture _capture;

    bool buildAlert(const char* line, uint32_t ingestMs, uint32_t sequence,
                    skyshield::Alert& alert) const {
        using namespace skyshield;

        // A pasted detector line goes through the real parser, so replayed
        // captures exercise exactly the production path.
        TTSKW07Diagnostics diagnostics;

        if (ttskw07ParseLine(line, ingestMs, sequence, alert, diagnostics) == TTSKW07_OK) {
            return true;
        }

        String token(line);
        token.trim();

        alertInit(alert);
        alert.timestampMs = ingestMs;
        alert.sequence = sequence;
        alert.sensorType = SENSOR_RF;
        alertSetSource(alert, "SERIAL_INJECT");

        // Shortcuts carry an explicit confidence because a human is asserting
        // one. Real TTSKW07 alerts leave confidence null; that difference is
        // intentional and visible on the HUD.
        if (token.equalsIgnoreCase("FPV")) {
            alert.threat = THREAT_FPV;
            alert.severity = SEVERITY_HIGH;
            alert.band = BAND_5_8;
            alert.distance = DISTANCE_NEAR;
            alert.hasConfidence = true;
            alert.confidence = 87;
            alertSetDroneClass(alert, "FPV");
            return true;
        }

        if (token.equalsIgnoreCase("MAVIC")) {
            alert.threat = THREAT_DJI;
            alert.severity = SEVERITY_MEDIUM;
            alert.band = BAND_2_4;
            alert.distance = DISTANCE_MID;
            alert.hasConfidence = true;
            alert.confidence = 72;
            alertSetDroneClass(alert, "MAVIC");
            return true;
        }

        if (token.equalsIgnoreCase("AUTEL")) {
            // Consistent with the TTSKW07 parser: the threat enum has no Autel
            // value, so the vendor lives in drone_class rather than being
            // misattributed to DJI.
            alert.threat = THREAT_UNKNOWN;
            alert.severity = SEVERITY_MEDIUM;
            alert.band = BAND_2_4;
            alert.distance = DISTANCE_MID;
            alert.hasConfidence = true;
            alert.confidence = 70;
            alertSetDroneClass(alert, "AUTEL");
            return true;
        }

        if (token.equalsIgnoreCase("UNKNOWN")) {
            alert.threat = THREAT_UNKNOWN;
            alert.severity = SEVERITY_HIGH;
            alert.band = BAND_MULTI;
            alert.distance = DISTANCE_NEAR;
            alert.hasConfidence = true;
            alert.confidence = 94;
            alertSetDroneClass(alert, "UNKNOWN");
            return true;
        }

        if (token.equalsIgnoreCase("CONTACT")) {
            alertInitContact(alert, ingestMs, sequence);
            alertSetSource(alert, "SERIAL_INJECT");
            return true;
        }

        return false;
    }
};
