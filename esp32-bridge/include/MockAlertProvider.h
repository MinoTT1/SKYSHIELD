#pragma once

#include "SkyShieldProtocol.h"

// Rotating simulated alerts for bench work. Produces the same skyshield::Alert
// struct as a real detector adapter, so the mock path and the live path share
// every downstream stage including the encoder.
class MockAlertProvider {
public:
    MockAlertProvider() : _index(0) {}

    void current(skyshield::Alert& alert, uint32_t timestampMs, uint32_t sequence) const {
        build(_index, alert, timestampMs, sequence);
    }

    void next(skyshield::Alert& alert, uint32_t timestampMs, uint32_t sequence) {
        _index = (_index + 1) % ALERT_COUNT;
        build(_index, alert, timestampMs, sequence);
    }

    void priorityTestAlert(uint32_t elapsedMs, skyshield::Alert& alert,
                           uint32_t timestampMs, uint32_t sequence) const {
        buildPriorityTest(priorityTestBlockIndex(elapsedMs), alert, timestampMs, sequence);
    }

    const char* priorityTestBlockLabel(uint32_t elapsedMs) const {
        switch (priorityTestBlockIndex(elapsedMs)) {
            case 0: return "PRIORITY TEST BLOCK 1 MEDIUM DJI";
            case 1: return "PRIORITY TEST BLOCK 2 HIGH FPV";
            case 2: return "PRIORITY TEST BLOCK 3 MEDIUM DJI";
            default: return "PRIORITY TEST BLOCK 4 ELEV UNKNOWN";
        }
    }

private:
    static const uint8_t ALERT_COUNT = 4;
    static const uint8_t PRIORITY_TEST_ALERT_COUNT = 4;
    static const uint32_t PRIORITY_TEST_BLOCK_MS = 10000;
    uint8_t _index;

    uint8_t priorityTestBlockIndex(uint32_t elapsedMs) const {
        return (elapsedMs / PRIORITY_TEST_BLOCK_MS) % PRIORITY_TEST_ALERT_COUNT;
    }

    static void applyBands(skyshield::Alert& alert, skyshield::BandStrength b12,
                           skyshield::BandStrength b24, skyshield::BandStrength b33,
                           skyshield::BandStrength b58) {
        alert.hasBands = true;
        alert.bands[0] = b12;
        alert.bands[1] = b24;
        alert.bands[2] = b33;
        alert.bands[3] = b58;
    }

    static void build(uint8_t index, skyshield::Alert& alert,
                      uint32_t timestampMs, uint32_t sequence) {
        using namespace skyshield;

        alertInit(alert);
        alert.timestampMs = timestampMs;
        alert.sequence = sequence;
        alert.sensorType = SENSOR_RF;
        alertSetSource(alert, "MOCK");

        switch (index) {
            case 0:
                alert.threat = THREAT_FPV;
                alert.severity = SEVERITY_HIGH;
                alert.band = BAND_5_8;
                alert.distance = DISTANCE_NEAR;
                alert.hasConfidence = true;
                alert.confidence = 87;
                alertSetDroneClass(alert, "FPV");
                applyBands(alert, STRENGTH_LOW, STRENGTH_LOW, STRENGTH_MED, STRENGTH_HIGH);
                break;

            case 1:
                alert.threat = THREAT_DJI;
                alert.severity = SEVERITY_MEDIUM;
                alert.band = BAND_2_4;
                alert.distance = DISTANCE_MID;
                alert.hasConfidence = true;
                alert.confidence = 72;
                alertSetDroneClass(alert, "MAVIC");
                applyBands(alert, STRENGTH_LOW, STRENGTH_MED, STRENGTH_MED, STRENGTH_LOW);
                break;

            case 2:
                alert.threat = THREAT_UNKNOWN;
                alert.severity = SEVERITY_CRITICAL;
                alert.band = BAND_MULTI;
                alert.distance = DISTANCE_NEAR;
                alert.hasConfidence = true;
                alert.confidence = 94;
                alertSetDroneClass(alert, "UNKNOWN");
                applyBands(alert, STRENGTH_HIGH, STRENGTH_MED, STRENGTH_MED, STRENGTH_HIGH);
                break;

            default:
                // Exercises the data-less contact path on the bench so the HUD
                // rendering of a no-classification detection stays tested.
                alertInitContact(alert, timestampMs, sequence);
                alertSetSource(alert, "MOCK");
                break;
        }
    }

    static void buildPriorityTest(uint8_t index, skyshield::Alert& alert,
                                  uint32_t timestampMs, uint32_t sequence) {
        using namespace skyshield;

        alertInit(alert);
        alert.timestampMs = timestampMs;
        alert.sequence = sequence;
        alert.sensorType = SENSOR_RF;
        alertSetSource(alert, "MOCK");
        alert.hasConfidence = true;

        switch (index) {
            case 1:
                alert.threat = THREAT_FPV;
                alert.severity = SEVERITY_HIGH;
                alert.band = BAND_5_8;
                alert.distance = DISTANCE_NEAR;
                alert.confidence = 87;
                alertSetDroneClass(alert, "FPV");
                applyBands(alert, STRENGTH_LOW, STRENGTH_LOW, STRENGTH_LOW, STRENGTH_HIGH);
                break;

            case 3:
                alert.threat = THREAT_UNKNOWN;
                alert.severity = SEVERITY_CRITICAL;
                alert.band = BAND_MULTI;
                alert.distance = DISTANCE_NEAR;
                alert.confidence = 94;
                alertSetDroneClass(alert, "UNKNOWN");
                applyBands(alert, STRENGTH_HIGH, STRENGTH_HIGH, STRENGTH_HIGH, STRENGTH_HIGH);
                break;

            default:
                alert.threat = THREAT_DJI;
                alert.severity = SEVERITY_MEDIUM;
                alert.band = BAND_2_4;
                alert.distance = DISTANCE_MID;
                alert.confidence = 72;
                alertSetDroneClass(alert, "MAVIC");
                applyBands(alert, STRENGTH_LOW, STRENGTH_HIGH, STRENGTH_LOW, STRENGTH_LOW);
                break;
        }
    }
};
