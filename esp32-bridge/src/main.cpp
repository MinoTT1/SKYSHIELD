#include <Arduino.h>
#include <NimBLEDevice.h>

#include "MockAlertProvider.h"

namespace {
MockAlertProvider mockAlerts;

const uint32_t ALERT_INTERVAL_MS = 4000;
const char* BLE_DEVICE_NAME = "SKYSHIELD-BRIDGE";
const char* SKYSHIELD_SERVICE_UUID = "9f4d0001-7c31-4f9b-9a4b-8f4c0f000001";
const char* ALERT_CHARACTERISTIC_UUID = "9f4d0002-7c31-4f9b-9a4b-8f4c0f000001";

uint32_t lastAlertMs = 0;
uint32_t bleConnectedAtMs = 0;
uint32_t sequence = 1;
bool bleClientConnected = false;
bool bleClientSubscribed = false;
NimBLECharacteristic* alertCharacteristic = nullptr;

class SkyShieldServerCallbacks : public NimBLEServerCallbacks {
public:
    void onConnect(NimBLEServer* server) override {
        (void)server;
        bleClientConnected = true;
        bleClientSubscribed = false;
        bleConnectedAtMs = millis();
        Serial.println("BLE client connected");
    }

    void onDisconnect(NimBLEServer* server) override {
        (void)server;
        bleClientConnected = false;
        bleClientSubscribed = false;
        Serial.println("BLE client disconnected");
        NimBLEDevice::startAdvertising();
    }
};

class SkyShieldAlertCallbacks : public NimBLECharacteristicCallbacks {
public:
    void onSubscribe(NimBLECharacteristic* characteristic, ble_gap_conn_desc* desc, uint16_t subValue) override {
        (void)characteristic;
        (void)desc;
        bleClientSubscribed = subValue > 0;

        if (bleClientSubscribed) {
            Serial.println("BLE client subscribed");
        } else {
            Serial.println("BLE client unsubscribed");
        }
    }
};

void initBle() {
    NimBLEDevice::init(BLE_DEVICE_NAME);
    NimBLEServer* server = NimBLEDevice::createServer();
    server->setCallbacks(new SkyShieldServerCallbacks());

    NimBLEService* service = server->createService(SKYSHIELD_SERVICE_UUID);

    alertCharacteristic = service->createCharacteristic(
        ALERT_CHARACTERISTIC_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    alertCharacteristic->setCallbacks(new SkyShieldAlertCallbacks());

    service->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->addServiceUUID(SKYSHIELD_SERVICE_UUID);
    advertising->setScanResponse(true);

    NimBLEDevice::startAdvertising();
    Serial.println("BLE advertising as SKYSHIELD-BRIDGE");
}

void publishAlert(const SkyShieldAlert& alert) {
    const String fullJson = alertToJson(alert, sequence);
    const String blePayload = alertToBleSimple(alert);

    Serial.print("SERIAL FULL: ");
    Serial.println(fullJson);
    Serial.print("BLE TX SIMPLE: ");
    Serial.println(blePayload);

    if (alertCharacteristic != nullptr) {
        alertCharacteristic->setValue(
            reinterpret_cast<uint8_t*>(const_cast<char*>(blePayload.c_str())),
            blePayload.length()
        );
        Serial.print("BLE TX len=");
        Serial.println(blePayload.length());

        if (bleClientConnected && bleClientSubscribed && ((millis() - bleConnectedAtMs) >= 1000)) {
            alertCharacteristic->notify();
            Serial.println("BLE notify sent");
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
