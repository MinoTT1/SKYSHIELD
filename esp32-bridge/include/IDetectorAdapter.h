#pragma once

class IDetectorAdapter {
public:
    virtual bool init() = 0;
    virtual bool connect() = 0;
    virtual void disconnect() = 0;
    virtual void poll() = 0;
};
