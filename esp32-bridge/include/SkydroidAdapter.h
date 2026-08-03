#pragma once

#include "IDetectorAdapter.h"

// Skydroid S10/S12 placeholder.
//
// NOT IMPLEMENTED. Kept only so the bring-up procedure in
// docs/SKYDROID_S12_BRINGUP.md has a landing place. begin() returns false, so
// selecting it in main.cpp fails loudly rather than silently producing no
// alerts.
//
// Per that document, no parser may be written until real S12 output has been
// captured from hardware. The serial settings are still unconfirmed, and
// guessing a format here would be the same mistake the TTSKW07 plan warns
// against. Implement only after captures exist in test_samples/.
class SkydroidAdapter : public IDetectorAdapter {
public:
    const char* name() const override { return "SKYDROID"; }

    bool begin() override {
        return false;
    }

    void end() override {}

    bool isReady() const override { return false; }

    bool poll(uint32_t sequence, skyshield::Alert& alert) override {
        (void)sequence;
        (void)alert;
        return false;
    }
};
