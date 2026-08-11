#pragma once

#include <Arduino.h>

#include "DW01Parser.h"
#include "IDetectorAdapter.h"
#include "RawSerialCapture.h"

// Tatusky DW01 detector adapter.
//
// ---------------------------------------------------------------------------
// TRANSPORT IS PROVISIONAL -- THE PARSING IS NOT
// ---------------------------------------------------------------------------
// The vendor describes the DW01 as pushing over BLE. This adapter reads from a
// serial port, mirroring TTSKW07Adapter, for one reason: the connection
// architecture is not decided yet. The DW01 may reach the watch through this
// bridge or connect to the watch directly, and if it comes through the bridge
// it may arrive on a UART or over BLE central.
//
// That decision only affects THIS file. Everything that matters -- the record
// format, the hex type codes, the vendor table, the threat mapping -- lives in
// DW01Parser.h, which is Arduino-free and portable to Monkey C unchanged if the
// detector ends up talking straight to the watch.
//
// So this adapter is scaffolding to be re-pointed when the hardware lands, not
// a claim about how the DW01 connects. It has NOT been run against a device.
class DW01Adapter : public IDetectorAdapter {
public:
    DW01Adapter(HardwareSerial& port, int8_t rxPin, int8_t txPin)
        : _port(port),
          _rxPin(rxPin),
          _txPin(txPin),
          _ready(false),
          _linesSeen(0),
          _detectionsParsed(0),
          _malformedLines(0),
          _unlistedTypeCodes(0) {}

    const char* name() const override { return "DW01"; }

    bool begin() override {
        _port.begin(BAUD_RATE, SERIAL_8N1, _rxPin, _txPin);
        _capture.begin(&_port);
        _ready = true;

        Serial.print("DW01 adapter up on UART rx=");
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

        // Latency point (a): a complete detector record is in hand. Sampled
        // before any parsing so the measurement includes normalization.
        const uint32_t ingestMs = millis();
        const char* line = _capture.getLine();

        _linesSeen += 1;

        skyshield::DW01Diagnostics diagnostics;
        const skyshield::DW01ParseResult result =
            skyshield::dw01ParseLine(line, ingestMs, sequence, alert, diagnostics);

        if (result == skyshield::DW01_NOT_A_DETECTION) {
            // Noise, banners and blanks are expected. Stay quiet so a noisy
            // link cannot flood the console.
            return false;
        }

        if (result != skyshield::DW01_OK) {
            _malformedLines += 1;
            Serial.print("DW01 MALFORMED RECORD: ");
            Serial.println(line);
            return false;
        }

        _detectionsParsed += 1;

        if (!diagnostics.typeCodeRecognized) {
            _unlistedTypeCodes += 1;
        }

        Serial.print("DW01 RAW: ");
        Serial.println(line);
        logDiagnostics(diagnostics);

        // Latency point (b): normalization complete. Both endpoints come from
        // the same CORE clock, so this is an exact detector-to-CORE latency
        // with no clock-sync assumptions.
        const uint32_t processedMs = millis();
        alert.timestampMs = processedMs;
        alert.hasDetectorLatency = true;
        alert.detectorLatencyMs = processedMs - ingestMs;

        return true;
    }

    uint32_t linesSeen() const { return _linesSeen; }
    uint32_t detectionsParsed() const { return _detectionsParsed; }
    uint32_t malformedLines() const { return _malformedLines; }
    uint32_t unlistedTypeCodes() const { return _unlistedTypeCodes; }

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
    uint32_t _unlistedTypeCodes;

    // The raw type code, frequency, R value and the C field are logged even
    // though the alert schema has no home for some of them. The type code
    // identifies an unlisted protocol worth reporting to the vendor, and the C
    // field is the open question this log is meant to help answer against the
    // real device.
    void logDiagnostics(const skyshield::DW01Diagnostics& diagnostics) const {
        Serial.print("DW01 fields: T=0x");

        if (diagnostics.typeCode < 0x10) {
            Serial.print("0");
        }

        Serial.print(diagnostics.typeCode, HEX);

        if (!diagnostics.typeCodeRecognized) {
            Serial.print(" (UNLISTED CODE, reported as unknown)");
        }

        if (diagnostics.hasFrequency) {
            Serial.print(" F=");
            Serial.print(diagnostics.frequencyMhz);
            Serial.print("MHz");
        }

        if (diagnostics.hasSignal) {
            // Vendor-confirmed 0-128, higher is stronger.
            Serial.print(" R=");
            Serial.print(diagnostics.signalValue);

            if (diagnostics.signalOutOfRange) {
                Serial.print(" (ABOVE THE VENDOR'S STATED 0-128)");
            }
        }

        // Logged verbatim and never interpreted. This is the field the vendor
        // did not explain; capturing it against real traffic is how we find out
        // what it means.
        if (diagnostics.hasCField) {
            Serial.print(" C=\"");
            Serial.print(diagnostics.cField);
            Serial.print("\"");

            if (diagnostics.cFieldTruncated) {
                Serial.print(" [truncated]");
            }
        } else {
            Serial.print(" C=<absent>");
        }

        Serial.println();
    }
};
