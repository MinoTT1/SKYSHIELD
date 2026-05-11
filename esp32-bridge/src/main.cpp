#include <Arduino.h>

#include "MockAlertProvider.h"

namespace {
MockAlertProvider mockAlerts;

const uint32_t ALERT_INTERVAL_MS = 4000;
uint32_t lastAlertMs = 0;
uint32_t sequence = 1;

void printAlert(const SkyShieldAlert& alert) {
    Serial.println(alertToJson(alert, sequence));
    sequence += 1;
}
}

void setup() {
    Serial.begin(115200);
    delay(250);

    Serial.println("SKYSHIELD ESP32 Bridge starting...");
    printAlert(mockAlerts.current());
    lastAlertMs = millis();
}

void loop() {
    const uint32_t now = millis();

    if (now - lastAlertMs >= ALERT_INTERVAL_MS) {
        lastAlertMs = now;
        printAlert(mockAlerts.next());
    }
}
