#pragma once

#include "SkyShieldAlert.h"

class MockAlertProvider {
public:
    MockAlertProvider() : _index(0) {}

    const SkyShieldAlert& current() const {
        return ALERTS[_index];
    }

    const SkyShieldAlert& next() {
        _index = (_index + 1) % ALERT_COUNT;
        return current();
    }

    const SkyShieldAlert& priorityTestAlert(uint32_t elapsedMs) const {
        return PRIORITY_TEST_ALERTS[priorityTestBlockIndex(elapsedMs)];
    }

    const char* priorityTestBlockLabel(uint32_t elapsedMs) const {
        return PRIORITY_TEST_BLOCK_LABELS[priorityTestBlockIndex(elapsedMs)];
    }

private:
    static const uint8_t ALERT_COUNT = 3;
    static const uint8_t PRIORITY_TEST_ALERT_COUNT = 4;
    static const uint32_t PRIORITY_TEST_BLOCK_MS = 10000;
    uint8_t _index;

    uint8_t priorityTestBlockIndex(uint32_t elapsedMs) const {
        return (elapsedMs / PRIORITY_TEST_BLOCK_MS) % PRIORITY_TEST_ALERT_COUNT;
    }

    static const SkyShieldAlert ALERTS[ALERT_COUNT];
    static const SkyShieldAlert PRIORITY_TEST_ALERTS[PRIORITY_TEST_ALERT_COUNT];
    static const char* PRIORITY_TEST_BLOCK_LABELS[PRIORITY_TEST_ALERT_COUNT];
};

const SkyShieldAlert MockAlertProvider::ALERTS[MockAlertProvider::ALERT_COUNT] = {
    { "FPV", "HIGH", "5.8GHz", "NEAR", 87, "LOW", "LOW", "MED", "HIGH", "FPV" },
    { "DJI", "MEDIUM", "2.4GHz", "MID", 72, "LOW", "MED", "MED", "LOW", "MAVIC" },
    { "UNKNOWN", "CRITICAL", "MULTI", "NEAR", 94, "HIGH", "MED", "MED", "HIGH", "UNKNOWN" }
};

const SkyShieldAlert MockAlertProvider::PRIORITY_TEST_ALERTS[MockAlertProvider::PRIORITY_TEST_ALERT_COUNT] = {
    { "DJI", "MEDIUM", "2.4GHz", "MID", 72, "LOW", "HIGH", "LOW", "LOW", "MAVIC" },
    { "FPV", "HIGH", "5.8GHz", "NEAR", 87, "LOW", "LOW", "LOW", "HIGH", "FPV" },
    { "DJI", "MEDIUM", "2.4GHz", "MID", 72, "LOW", "HIGH", "LOW", "LOW", "MAVIC" },
    { "UNKNOWN", "CRITICAL", "MULTI", "NEAR", 94, "HIGH", "HIGH", "HIGH", "HIGH", "UNKNOWN" }
};

const char* MockAlertProvider::PRIORITY_TEST_BLOCK_LABELS[MockAlertProvider::PRIORITY_TEST_ALERT_COUNT] = {
    "PRIORITY TEST BLOCK 1 MEDIUM DJI",
    "PRIORITY TEST BLOCK 2 HIGH FPV",
    "PRIORITY TEST BLOCK 3 MEDIUM DJI",
    "PRIORITY TEST BLOCK 4 ELEV UNKNOWN"
};
