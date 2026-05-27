#pragma once

#include <Arduino.h>

#include "SkyShieldAlert.h"

class DetectorInputAdapter {
public:
    bool readAlert(NormalizedAlert& alert, String& rawDetectorPayload) {
        rawDetectorPayload = "";

        // TODO: connect live detector sources here.
        // Planned input paths:
        // - UART serial packets from a detector board
        // - UDP packets from a local RF processor
        // - MQTT messages from a gateway
        // - detector-specific API adapters
        if (!Serial.available()) {
            return false;
        }

        String line = Serial.readStringUntil('\n');
        line.trim();

        if (line.length() == 0) {
            return false;
        }

        line = expandShortcut(line);

        if (!parseS2Line(line, alert)) {
            Serial.print("INVALID SERIAL DETECTOR INPUT: ");
            Serial.println(line);
            return false;
        }

        rawDetectorPayload = line;
        return true;
    }

private:
    char _droneClass[24];

    String expandShortcut(const String& line) const {
        if (line.equalsIgnoreCase("FPV")) {
            return "S2|F|H|58|N|FPV";
        }

        if (line.equalsIgnoreCase("MAVIC")) {
            return "S2|D|M|24|M|MAVIC";
        }

        if (line.equalsIgnoreCase("AUTEL")) {
            return "S2|D|M|24|M|AUTEL";
        }

        if (line.equalsIgnoreCase("UNKNOWN")) {
            return "S2|U|C|X|N|UNKNOWN";
        }

        return line;
    }

    bool parseS2Line(const String& line, NormalizedAlert& alert) {
        if (!line.startsWith("S2|")) {
            return false;
        }

        String fields[6];

        if (!extractS2Fields(line, fields)) {
            return false;
        }

        if (!fields[0].equals("S2")) {
            return false;
        }

        const char* rfType = mapRfType(fields[1]);
        const char* severity = mapSeverity(fields[2]);
        const char* band = mapBand(fields[3]);
        const char* strength = mapStrength(fields[4]);

        if ((rfType == nullptr) || (severity == nullptr) || (band == nullptr) || (strength == nullptr)) {
            return false;
        }

        if (fields[5].length() == 0 || fields[5].length() >= sizeof(_droneClass)) {
            return false;
        }

        fields[5].toCharArray(_droneClass, sizeof(_droneClass));

        alert = {
            rfType,
            severity,
            band,
            strength,
            _droneClass
        };

        return true;
    }

    bool extractS2Fields(const String& line, String fields[6]) const {
        int start = 0;

        for (uint8_t i = 0; i < 6; i += 1) {
            const int pipeIndex = line.indexOf('|', start);

            if (i < 5) {
                if (pipeIndex < 0) {
                    return false;
                }

                fields[i] = line.substring(start, pipeIndex);
                start = pipeIndex + 1;
            } else {
                if (pipeIndex >= 0) {
                    return false;
                }

                fields[i] = line.substring(start);
            }

            fields[i].trim();
        }

        return true;
    }

    const char* mapRfType(const String& value) const {
        if (value.equals("F")) {
            return "F";
        }

        if (value.equals("D")) {
            return "D";
        }

        if (value.equals("U")) {
            return "U";
        }

        return nullptr;
    }

    const char* mapSeverity(const String& value) const {
        if (value.equals("L")) {
            return "L";
        }

        if (value.equals("M")) {
            return "M";
        }

        if (value.equals("H")) {
            return "H";
        }

        if (value.equals("C")) {
            return "C";
        }

        return nullptr;
    }

    const char* mapBand(const String& value) const {
        if (value.equals("12")) {
            return "12";
        }

        if (value.equals("24")) {
            return "24";
        }

        if (value.equals("33")) {
            return "33";
        }

        if (value.equals("58")) {
            return "58";
        }

        if (value.equals("X")) {
            return "X";
        }

        return nullptr;
    }

    const char* mapStrength(const String& value) const {
        if (value.equals("F")) {
            return "F";
        }

        if (value.equals("M")) {
            return "M";
        }

        if (value.equals("N")) {
            return "N";
        }

        return nullptr;
    }
};
