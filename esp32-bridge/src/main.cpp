#include <Arduino.h>
#include <NimBLEDevice.h>

#include "DetectorInputAdapter.h"
#include "MockAlertProvider.h"
#include "SkyShieldCodec.h"

namespace {
MockAlertProvider mockAlerts;
DetectorInputAdapter serialInject;

const bool MOCK_MODE = false;
const bool PRIORITY_TEST_MODE = false;
const uint32_t ALERT_INTERVAL_MS = 4000;
const char* BLE_DEVICE_NAME = "SKYSHIELD-BRIDGE";
const char* SKYSHIELD_SERVICE_UUID = "9f4d0001-7c31-4f9b-9a4b-8f4c0f000001";
const char* ALERT_CHARACTERISTIC_UUID = "9f4d0002-7c31-4f9b-9a4b-8f4c0f000001";

// A CBOR alert is 29-45 bytes, which does not fit the 20-byte payload of an
// unnegotiated 23-byte ATT MTU. Request headroom at startup. See
// docs/wire-protocol.md.
const uint16_t BLE_PREFERRED_MTU = 185;

uint32_t lastAlertMs = 0;
uint32_t bleConnectedAtMs = 0;
uint32_t mockStartedAtMs = 0;
uint32_t sequence = 1;
bool bleClientConnected = false;
bool bleClientSubscribed = false;
NimBLECharacteristic* alertCharacteristic = nullptr;

uint8_t payloadBuffer[skyshield::MAX_PAYLOAD_BYTES];

const char* modeLabel() {
    return MOCK_MODE ? "MOCK" : "SERIAL_INJECT";
}

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
    NimBLEDevice::setMTU(BLE_PREFERRED_MTU);

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

void printAlertSummary(const skyshield::Alert& alert) {
    using namespace skyshield;

    Serial.print("ALERT kind=");
    Serial.print(alertKindName(alert.alertKind));
    Serial.print(" sensor=");
    Serial.print(sensorTypeName(alert.sensorType));
    Serial.print(" threat=");
    Serial.print(threatName(alert.threat));
    Serial.print(" severity=");
    Serial.print(severityName(alert.severity));
    Serial.print(" band=");
    Serial.print(bandName(alert.band));
    Serial.print(" strength=");
    Serial.print(distanceName(alert.distance));
    Serial.print(" confidence=");

    if (alert.hasConfidence) {
        Serial.print(alert.confidence);
    } else {
        Serial.print("none");
    }

    Serial.print(" class=");
    Serial.print(alert.hasDroneClass ? alert.droneClass : "-");
    Serial.print(" seq=");
    Serial.print(alert.sequence);
    Serial.print(" t=");
    Serial.print(alert.timestampMs);

    if (alert.hasDetectorLatency) {
        Serial.print(" detector_to_core=");
        Serial.print(alert.detectorLatencyMs);
        Serial.print("ms");
    }

    Serial.println();
}

void printPayloadHex(const uint8_t* payload, size_t length) {
    Serial.print("BLE TX CBOR len=");
    Serial.print(length);
    Serial.print(" bytes=");

    for (size_t i = 0; i < length; i += 1) {
        if (payload[i] < 0x10) {
            Serial.print('0');
        }

        Serial.print(payload[i], HEX);
    }

    Serial.println();
}

// Encodes and transmits one alert. Refuses to transmit a packet that failed to
// encode: a truncated CBOR map would decode to a plausible-but-wrong alert.
void publishAlert(const skyshield::Alert& alert) {
    printAlertSummary(alert);

    const size_t length = skyshield::encodeAlert(alert, payloadBuffer, sizeof(payloadBuffer));

    if (length == 0) {
        Serial.println("ENCODE FAILED: alert not transmitted");
        return;
    }

    printPayloadHex(payloadBuffer, length);

    if (alertCharacteristic == nullptr) {
        return;
    }

    // setValue keeps the most recent alert readable, so a reconnecting watch
    // can recover current state without waiting for the next notification.
    alertCharacteristic->setValue(payloadBuffer, length);

    if (bleClientConnected && bleClientSubscribed && ((millis() - bleConnectedAtMs) >= 1000)) {
        alertCharacteristic->notify();
        Serial.println("BLE notify sent");
    }

    sequence += 1;
}

void publishCurrentMockAlert(uint32_t now) {
    skyshield::Alert alert;

    if (PRIORITY_TEST_MODE) {
        const uint32_t elapsedMs = now - mockStartedAtMs;
        Serial.println(mockAlerts.priorityTestBlockLabel(elapsedMs));
        mockAlerts.priorityTestAlert(elapsedMs, alert, millis(), sequence);
        publishAlert(alert);
        return;
    }

    mockAlerts.next(alert, millis(), sequence);
    publishAlert(alert);
}

void pollSerialInject() {
    skyshield::Alert alert;
    String rawPayload;

    // Latency point (a): the moment input was ingested.
    const uint32_t ingestMs = millis();

    if (!serialInject.readAlert(alert, rawPayload, ingestMs, sequence)) {
        return;
    }

    Serial.print("RAW INJECT INPUT: ");
    Serial.println(rawPayload);

    // Latency point (b): normalization complete, about to transmit.
    const uint32_t processedMs = millis();
    alert.timestampMs = processedMs;
    alert.hasDetectorLatency = true;
    alert.detectorLatencyMs = processedMs - ingestMs;

    publishAlert(alert);
}
}  // namespace

void setup() {
    Serial.begin(115200);
    delay(250);

    Serial.println("SKYSHIELD ESP32 Bridge starting...");
    Serial.print("MODE: ");
    Serial.println(modeLabel());
    Serial.print("PROTOCOL VERSION: ");
    Serial.println(skyshield::PROTOCOL_VERSION);

    initBle();

    if (MOCK_MODE) {
        mockStartedAtMs = millis();

        skyshield::Alert alert;

        if (PRIORITY_TEST_MODE) {
            Serial.println("PRIORITY TEST MODE: ON");
            Serial.println(mockAlerts.priorityTestBlockLabel(0));
            mockAlerts.priorityTestAlert(0, alert, millis(), sequence);
        } else {
            mockAlerts.current(alert, millis(), sequence);
        }

        publishAlert(alert);
    } else {
        Serial.println("SERIAL_INJECT mode: type FPV, MAVIC, AUTEL, UNKNOWN or CONTACT");
    }

    lastAlertMs = millis();
}

void loop() {
    const uint32_t now = millis();

    // Serial injection is checked every loop so an operator-typed alert is not
    // delayed by the mock cadence.
    if (!MOCK_MODE) {
        pollSerialInject();
        return;
    }

    if (now - lastAlertMs >= ALERT_INTERVAL_MS) {
        lastAlertMs = now;
        publishCurrentMockAlert(now);
    }
}
