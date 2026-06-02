#pragma once

#include <Arduino.h>

// Lightweight line capture helper for future TTSKW07Adapter work.
// Intended input sources:
// - USB Virtual COM / UART at 115200 8N1
// - raw detector packet capture
// - future ASCII protocol parser development
class RawSerialCapture {
public:
    static const size_t MAX_LINE_LENGTH = 160;

    RawSerialCapture()
        : _input(nullptr),
          _lineReady(false),
          _bufferLength(0) {
        _buffer[0] = '\0';
        _line[0] = '\0';
    }

    void begin(Stream* input) {
        _input = input;
        clear();
    }

    void poll() {
        if (_input == nullptr) {
            return;
        }

        while (_input->available() > 0) {
            const char ch = static_cast<char>(_input->read());

            if ((ch == '\n') || (ch == '\r')) {
                commitLine();
                continue;
            }

            if (!isPrintableAscii(ch)) {
                continue;
            }

            if (_bufferLength < (MAX_LINE_LENGTH - 1)) {
                _buffer[_bufferLength] = ch;
                _bufferLength += 1;
                _buffer[_bufferLength] = '\0';
            }
        }
    }

    bool hasLine() const {
        return _lineReady;
    }

    const char* getLine() {
        _lineReady = false;
        return _line;
    }

    void clear() {
        _lineReady = false;
        _bufferLength = 0;
        _buffer[0] = '\0';
        _line[0] = '\0';
    }

private:
    Stream* _input;
    bool _lineReady;
    size_t _bufferLength;
    char _buffer[MAX_LINE_LENGTH];
    char _line[MAX_LINE_LENGTH];

    bool isPrintableAscii(char ch) const {
        return (ch >= 32) && (ch <= 126);
    }

    void commitLine() {
        trimBuffer();

        if (_bufferLength == 0) {
            _buffer[0] = '\0';
            return;
        }

        copyBufferToLine();
        _lineReady = true;
        _bufferLength = 0;
        _buffer[0] = '\0';
    }

    void trimBuffer() {
        while ((_bufferLength > 0) && isWhitespace(_buffer[_bufferLength - 1])) {
            _bufferLength -= 1;
            _buffer[_bufferLength] = '\0';
        }

        size_t start = 0;

        while ((start < _bufferLength) && isWhitespace(_buffer[start])) {
            start += 1;
        }

        if (start == 0) {
            return;
        }

        size_t writeIndex = 0;

        while (start < _bufferLength) {
            _buffer[writeIndex] = _buffer[start];
            writeIndex += 1;
            start += 1;
        }

        _bufferLength = writeIndex;
        _buffer[_bufferLength] = '\0';
    }

    bool isWhitespace(char ch) const {
        return (ch == ' ') || (ch == '\t');
    }

    void copyBufferToLine() {
        for (size_t i = 0; i <= _bufferLength; i += 1) {
            _line[i] = _buffer[i];
        }
    }
};
