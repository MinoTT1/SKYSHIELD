#pragma once

#include "IDetectorAdapter.h"

class TTSKW07Adapter : public IDetectorAdapter {
public:
    bool init() override {
        // Future TTSKW07 setup:
        // - initialize USB Virtual COM transport
        // - configure 115200 8N1 serial parameters
        // - prepare ASCII protocol parser state
        return false;
    }

    bool connect() override {
        // Future TTSKW07 connection flow:
        // - open detector USB Virtual COM session
        // - confirm detector presence/ready state
        return false;
    }

    void disconnect() override {
        // Future TTSKW07 disconnect flow:
        // - close Virtual COM session
        // - clear parser and detector state
    }

    void poll() override {
        // Future TTSKW07 polling flow:
        // - read ASCII protocol bytes in realtime
        // - parse detector events
        // - generate SkyShieldEvent records for normalization
    }
};
