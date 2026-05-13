#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#include "MockAlertProvider.h"

namespace {
MockAlertProvider mockAlerts;

const uint32_t ALERT_INTERVAL_MS = 4000;
const char* BLE_DEVICE_NAME = "SKYSHIELD-BRIDGE";
const char* SKYSHIELD_SERVICE_UUID = "9f4d0001-7c31-4f9b-9a4b-8f4c0f000001";
const char* ALERT_CHARACTERISTIC_UUID = "9f4d0002-7c31-4f9b-9a4b-8f4c0f000001";

uint32_t lastAlertMs = 0;
uint32_t sequence = 1;
bool bleClientConnected = false;
BLECharacteristic* alertCharacteristic = nullptr;

class SkyShieldServerCallbacks : public BLEServerCallbacks {
public:
    void onConnect(BLEServer* server) override {
        (void)server;
        bleClientConnected = true;
        Serial.println("BLE client connected");
    }

    void onDisconnect(BLEServer* server) override {
        (void)server;
        bleClientConnected = false;
        Serial.println("BLE client disconnected");
        BLEDevice::startAdvertising();
    }
};

void initBle() {
    BLEDevice::init(BLE_DEVICE_NAME);

    BLEServer* server = BLEDevice::createServer();
    server->setCallbacks(new SkyShieldServerCallbacks());

    BLEService* service = server->createService(SKYSHIELD_SERVICE_UUID);

    alertCharacteristic = service->createCharacteristic(
        ALERT_CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    alertCharacteristic->addDescriptor(new BLE2902());

    service->start();

    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SKYSHIELD_SERVICE_UUID);
    advertising->setScanResponse(true);
    advertising->setMinPreferred(0x06);
    advertising->setMinPreferred(0x12);

    BLEDevice::startAdvertising();
    Serial.println("BLE advertising as SKYSHIELD-BRIDGE");
}

void publishAlert(const SkyShieldAlert& alert) {
    const String json = alertToJson(alert, sequence);

    Serial.println(json);

    if (alertCharacteristic != nullptr) {
        alertCharacteristic->setValue(json.c_str());

        if (bleClientConnected) {
            alertCharacteristic->notify();
        }
    }

    sequence += 1;
}
}

void setup() {
    Serial.begin(115200);
    delay(250);

    Serial.println("SKYSHIELD ESP32 Bridge starting...");
    initBle();
    publishAlert(mockAlerts.current());
    lastAlertMs = millis();
}

void loop() {
    const uint32_t now = millis();

    if (now - lastAlertMs >= ALERT_INTERVAL_MS) {
        lastAlertMs = now;
        publishAlert(mockAlerts.next());
    }
}
