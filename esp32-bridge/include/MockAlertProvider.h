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

private:
    static const uint8_t ALERT_COUNT = 3;
    uint8_t _index;

    static const SkyShieldAlert ALERTS[ALERT_COUNT];
};

const SkyShieldAlert MockAlertProvider::ALERTS[MockAlertProvider::ALERT_COUNT] = {
    { "FPV", "HIGH", "5.8GHz", "NEAR", 87 },
    { "DJI", "MEDIUM", "2.4GHz", "MID", 72 },
    { "UNKNOWN", "CRITICAL", "MULTI", "NEAR", 94 }
};
