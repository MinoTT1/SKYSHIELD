#pragma once

#include <Arduino.h>

#include "IDetectorAdapter.h"
#include "RawSerialCapture.h"
#include "TTSKW07Parser.h"

// Live Tatusky TTSKW07 detector adapter.
//
// Transport is vendor-confirmed (docs/TTSKW07_INTEGRATION_PLAN.md):
// 115200 8N1, no parity, no flow control, ASCII lines.
//
// On the ESP32-S3 the USB CDC port is the debug console, so the detector is
// wired to a hardware UART instead. Pins are supplied by the caller.
class TTSKW07Adapter : public IDetectorAdapter {
public:
    TTSKW07Adapter(HardwareSerial& port, int8_t rxPin, int8_t txPin)
        : _port(port),
          _rxPin(rxPin),
          _txPin(txPin),
          _ready(false),
          _linesSeen(0),
          _detectionsParsed(0),
          _malformedLines(0) {}

    const char* name() const override { return "TTSKW07"; }

    bool begin() override {
        _port.begin(BAUD_RATE, SERIAL_8N1, _rxPin, _txPin);
        _capture.begin(&_port);
        _ready = true;

        Serial.print("TTSKW07 adapter up on UART rx=");
        Serial.print(_rxPin);
        Serial.print(" tx=");
        Serial.print(_txPin);
        Serial.print(" @");
        Serial.println(BAUD_RATE);

        return true;
    }

    void end() override {
        _capture.clear();
        _port.end();
        _ready = false;
    }

    bool isReady() const override { return _ready; }

    bool poll(uint32_t sequence, skyshield::Alert& alert) override {
        if (!_ready) {
            return false;
        }

        _capture.poll();

        if (!_capture.hasLine()) {
            return false;
        }

        // Latency point (a): a complete detector line is now in hand. Sampled
        // before any parsing work so the measurement includes normalization.
        const uint32_t ingestMs = millis();
        const char* line = _capture.getLine();

        _linesSeen += 1;

        skyshield::TTSKW07Diagnostics diagnostics;
        const skyshield::TTSKW07ParseResult result =
            skyshield::ttskw07ParseLine(line, ingestMs, sequence, alert, diagnostics);

        if (result == skyshield::TTSKW07_NOT_A_DETECTION) {
            // Noise, banners and blank lines are expected on a UART. Stay quiet
            // so a noisy link cannot flood the console.
            return false;
        }

        if (result != skyshield::TTSKW07_OK) {
            _malformedLines += 1;
            Serial.print("TTSKW07 MALFORMED LINE: ");
            Serial.println(line);
            return false;
        }

        _detectionsParsed += 1;

        Serial.print("TTSKW07 RAW: ");
        Serial.println(line);
        logDiagnostics(diagnostics);

        // Latency point (b): normalization complete. Both endpoints come from
        // the same CORE clock, so this difference is an exact detector-to-CORE
        // latency with no clock-sync assumptions.
        const uint32_t processedMs = millis();
        alert.timestampMs = processedMs;
        alert.hasDetectorLatency = true;
        alert.detectorLatencyMs = processedMs - ingestMs;

        return true;
    }

    uint32_t linesSeen() const { return _linesSeen; }
    uint32_t detectionsParsed() const { return _detectionsParsed; }
    uint32_t malformedLines() const { return _malformedLines; }

private:
    static const uint32_t BAUD_RATE = 115200;

    HardwareSerial& _port;
    int8_t _rxPin;
    int8_t _txPin;
    bool _ready;
    RawSerialCapture _capture;
    uint32_t _linesSeen;
    uint32_t _detectionsParsed;
    uint32_t _malformedLines;

    // RSSI and frequency are preserved from the raw line for the log even
    // though the alert schema carries neither.
    void logDiagnostics(const skyshield::TTSKW07Diagnostics& diagnostics) const {
        Serial.print("TTSKW07 detector fields: type=");
        Serial.print(diagnostics.rawType);

        if (diagnostics.detectionTime[0] != '\0') {
            Serial.print(" time=");
            Serial.print(diagnostics.detectionTime);
        }

        if (diagnostics.hasRssi) {
            Serial.print(" rssi=");
            Serial.print(diagnostics.rssiDbm);
            Serial.print("dBm");
        }

        if (diagnostics.hasFrequency) {
            Serial.print(" freq=");
            Serial.print(diagnostics.frequencyMhz);
            Serial.print("MHz");
        }

        Serial.println();
    }
};
