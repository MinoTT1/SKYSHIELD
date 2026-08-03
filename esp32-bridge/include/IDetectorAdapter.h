#pragma once

#include "SkyShieldProtocol.h"

// Contract every detector source implements. main.cpp drives detectors only
// through this interface, so adding a detector never means touching the BLE,
// encoding or publishing path.
//
// Previously this interface existed but nothing called through it; the
// firmware talked to a concrete class directly (audit Finding A-2 / F-1).
class IDetectorAdapter {
public:
    virtual ~IDetectorAdapter() {}

    // Short label carried in the alert's source field and used in logs.
    virtual const char* name() const = 0;

    // Opens the transport. Returns false if the detector cannot be brought up;
    // the caller decides whether that is fatal.
    virtual bool begin() = 0;

    virtual void end() = 0;

    // Whether the transport is currently usable.
    virtual bool isReady() const = 0;

    // MUST be non-blocking: it is called from the main loop alongside BLE
    // housekeeping, and a blocking read here stalls the whole bridge.
    //
    // Returns true and fills alert when a complete, valid detection is
    // available. The implementation is responsible for setting timestampMs and
    // detectorLatencyMs, since only it knows when the raw input was ingested.
    virtual bool poll(uint32_t sequence, skyshield::Alert& alert) = 0;
};
