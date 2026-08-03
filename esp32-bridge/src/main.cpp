#include <Arduino.h>
#include <NimBLEDevice.h>

#include "IDetectorAdapter.h"
#include "MockAlertProvider.h"
#include "SerialInjectAdapter.h"
#include "SkyShieldCodec.h"
#include "TTSKW07Adapter.h"

namespace {

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

enum DetectorSelection : uint8_t {
    // Live Tatusky TTSKW07 on a hardware UART.
    DETECTOR_TTSKW07 = 0,
    // Operator types alerts into the USB console. Bench only, not a detector.
    DETECTOR_SERIAL_INJECT = 1,
    // Rotating simulated alerts on a timer. Bench only.
    DETECTOR_MOCK = 2
};

const DetectorSelection ACTIVE_DETECTOR = DETECTOR_SERIAL_INJECT;

// TTSKW07 wiring. The USB CDC port is the debug console on the ESP32-S3, so
// the detector gets its own UART.
const int8_t TTSKW07_RX_PIN = 18;
const int8_t TTSKW07_TX_PIN = 17;

const bool PRIORITY_TEST_MODE = false;
const uint32_t MOCK_INTERVAL_MS = 4000;

const char* BLE_DEVICE_NAME = "SKYSHIELD-BRIDGE";
const char* SKYSHIELD_SERVICE_UUID = "9f4d0001-7c31-4f9b-9a4b-8f4c0f000001";
const char* ALERT_CHARACTERISTIC_UUID = "9f4d0002-7c31-4f9b-9a4b-8f4c0f000001";

// A CBOR alert is 29-45 bytes and does not fit the 20-byte payload of an
// unnegotiated 23-byte ATT MTU. See docs/wire-protocol.md.
const uint16_t BLE_PREFERRED_MTU = 185;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

TTSKW07Adapter ttskw07Adapter(Serial1, TTSKW07_RX_PIN, TTSKW07_TX_PIN);
SerialInjectAdapter serialInjectAdapter;
MockAlertProvider mockAlerts;

IDetectorAdapter* detector = nullptr;

uint32_t lastMockMs = 0;
uint32_t mockStartedAtMs = 0;
uint32_t sequence = 1;
bool bleClientConnected = false;
bool bleClientSubscribed = false;
uint32_t bleConnectedAtMs = 0;
NimBLECharacteristic* alertCharacteristic = nullptr;

uint8_t payloadBuffer[skyshield::MAX_PAYLOAD_BYTES];

bool usingMockProvider() {
    return ACTIVE_DETECTOR == DETECTOR_MOCK;
}

const char* activeSourceLabel() {
    if (usingMockProvider()) {
        return "MOCK";
    }

    return (detector != nullptr) ? detector->name() : "NONE";
}

// ---------------------------------------------------------------------------
// BLE
// ---------------------------------------------------------------------------

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
        Serial.println(bleClientSubscribed ? "BLE client subscribed" : "BLE client unsubscribed");
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

// ---------------------------------------------------------------------------
// Publishing
// ---------------------------------------------------------------------------

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
// encode rather than sending a truncated map, which would decode to a
// plausible-but-wrong alert.
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

    // Keeps the most recent alert readable so a reconnecting watch can recover
    // current state without waiting for the next notification.
    alertCharacteristic->setValue(payloadBuffer, length);

    if (bleClientConnected && bleClientSubscribed && ((millis() - bleConnectedAtMs) >= 1000)) {
        alertCharacteristic->notify();

        // Latency point (b): handed to the BLE stack. The watch records point
        // (c) on receipt; see docs/latency-measurement.md for why the two
        // clocks cannot be differenced directly.
        Serial.print("BLE notify sent seq=");
        Serial.print(alert.sequence);
        Serial.print(" core_tx_ms=");
        Serial.println(alert.timestampMs);
    }

    sequence += 1;
}

void pollDetector() {
    if (detector == nullptr) {
        return;
    }

    skyshield::Alert alert;

    if (detector->poll(sequence, alert)) {
        publishAlert(alert);
    }
}

void pollMockProvider(uint32_t now) {
    if ((now - lastMockMs) < MOCK_INTERVAL_MS) {
        return;
    }

    lastMockMs = now;

    skyshield::Alert alert;

    if (PRIORITY_TEST_MODE) {
        const uint32_t elapsedMs = now - mockStartedAtMs;
        Serial.println(mockAlerts.priorityTestBlockLabel(elapsedMs));
        mockAlerts.priorityTestAlert(elapsedMs, alert, millis(), sequence);
    } else {
        mockAlerts.next(alert, millis(), sequence);
    }

    publishAlert(alert);
}

void selectDetector() {
    switch (ACTIVE_DETECTOR) {
        case DETECTOR_TTSKW07:
            detector = &ttskw07Adapter;
            break;

        case DETECTOR_SERIAL_INJECT:
            detector = &serialInjectAdapter;
            break;

        default:
            detector = nullptr;  // mock provider is not a detector
            break;
    }

    if (detector == nullptr) {
        return;
    }

    if (!detector->begin()) {
        Serial.print("DETECTOR FAILED TO START: ");
        Serial.println(detector->name());
        detector = nullptr;
    }
}

}  // namespace

void setup() {
    Serial.begin(115200);
    delay(250);

    Serial.println("SKYSHIELD ESP32 Bridge starting...");
    Serial.print("PROTOCOL VERSION: ");
    Serial.println(skyshield::PROTOCOL_VERSION);

    initBle();
    selectDetector();

    Serial.print("ACTIVE SOURCE: ");
    Serial.println(activeSourceLabel());

    if (usingMockProvider()) {
        mockStartedAtMs = millis();
        lastMockMs = millis();

        skyshield::Alert alert;

        if (PRIORITY_TEST_MODE) {
            Serial.println("PRIORITY TEST MODE: ON");
            Serial.println(mockAlerts.priorityTestBlockLabel(0));
            mockAlerts.priorityTestAlert(0, alert, millis(), sequence);
        } else {
            mockAlerts.current(alert, millis(), sequence);
        }

        publishAlert(alert);
    }
}

void loop() {
    // Detectors are polled every iteration and must be non-blocking, so an
    // alert is published as soon as its line arrives rather than waiting on a
    // fixed cadence. Only the mock provider is timer-driven.
    if (usingMockProvider()) {
        pollMockProvider(millis());
        return;
    }

    pollDetector();
}
