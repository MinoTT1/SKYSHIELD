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

// A CBOR alert is 29-56 bytes and does not fit the 20-byte payload of an
// unnegotiated 23-byte ATT MTU. See docs/wire-protocol.md.
const uint16_t BLE_PREFERRED_MTU = 185;

// ATT header overhead on a notification: 1 opcode + 2 handle. The usable
// payload is therefore MTU - 3.
const uint16_t BLE_ATT_HEADER_BYTES = 3;

// -------------------------- TEMPORARY MTU DIAGNOSTICS ----------------------
// Bench instrumentation for the MTU sanity test. Serial-logging only: it does
// not change what is transmitted. Remove once the negotiated MTU is confirmed
// on real Enduro 2 hardware.
//
// WORST-CASE TEST LINE. Of the captured TTSKW07 samples, this one produces the
// largest CBOR payload, because drone_class is the only variable-length field
// and FPV_ANALOG is the longest value at 10 characters:
//
//   TTSKW07 TIME=00:00:09 TYPE=FPV_ANALOG BAND=5.8GHz FREQ_MHZ=5865 RSSI=-45DBM SIGNAL=NEAR
//
// Paste that into the serial console with ACTIVE_DETECTOR =
// DETECTOR_SERIAL_INJECT. Expected encoded size:
//
//   49 bytes  typical, at roughly an hour of uptime
//   56 bytes  absolute upper bound, once timestamp_ms, sequence and
//             detector_latency_ms all reach 32-bit maximums
//
// Size grows with uptime because timestamp_ms is encoded in the shortest CBOR
// form that fits, so a freshly booted board emits a few bytes less than one
// that has been running for hours. Structural maximum for any detector is
// about 69 bytes, reached only if drone_class fills its 23-character capacity.
const bool LOG_MTU_DIAGNOSTICS = true;

size_t largestPayloadSeen = 0;

// The MTU is deliberately NOT cached. It used to be snapshotted into a
// negotiatedMtu variable that both the connect callback and the MTU-exchange
// callback wrote to, and the send path then trusted that snapshot. Any path
// that left the snapshot stale -- callback ordering, a missed MTU event, or a
// reconnect issuing a fresh connection handle -- made the send path compute
// the usable payload from a dead value while the live link was fine.
//
// Instead we keep the connection handle and ask the stack for the MTU at the
// moment we need it, so every reader gets the same live answer by construction.
const uint16_t BLE_CONN_HANDLE_INVALID = 0xFFFF;

NimBLEServer* bleServer = nullptr;
uint16_t bleConnHandle = BLE_CONN_HANDLE_INVALID;
// ---------------------------------------------------------------------------

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

// Reports the usable notification payload for a given MTU, or 0 if unknown.
uint16_t usablePayloadBytes(uint16_t mtu) {
    if (mtu <= BLE_ATT_HEADER_BYTES) {
        return 0;
    }

    return mtu - BLE_ATT_HEADER_BYTES;
}

// THE single source of truth for the ATT MTU. Reads the live value from the
// stack for the currently connected client. Returns 0 when there is no usable
// connection, which callers must treat as "unknown" rather than as a small
// MTU, so an unknown value can never trigger a false size failure.
uint16_t currentMtu() {
    if ((bleServer == nullptr) || (bleConnHandle == BLE_CONN_HANDLE_INVALID)) {
        return 0;
    }

    return bleServer->getPeerMTU(bleConnHandle);
}

uint16_t currentUsablePayloadBytes() {
    return usablePayloadBytes(currentMtu());
}

class SkyShieldServerCallbacks : public NimBLEServerCallbacks {
public:
    void onConnect(NimBLEServer* server) override {
        (void)server;
        markConnected();
        Serial.println("BLE client connected");
    }

    // Overload carrying the connection descriptor. NimBLE invokes both onConnect
    // overloads, so this records the connection handle that every later MTU read
    // depends on. A reconnect issues a new handle and this keeps it current.
    void onConnect(NimBLEServer* server, ble_gap_conn_desc* desc) override {
        markConnected();

        if ((server != nullptr) && (desc != nullptr)) {
            bleServer = server;
            bleConnHandle = desc->conn_handle;
        }

        if (!LOG_MTU_DIAGNOSTICS) {
            return;
        }

        // Reads the same live source the send path uses, so these two log lines
        // cannot disagree. Usually still 23 here, because the central normally
        // starts MTU exchange just after connecting.
        Serial.print("MTU at connect: ");
        Serial.print(currentMtu());
        Serial.print(" (requested ");
        Serial.print(BLE_PREFERRED_MTU);
        Serial.println(")");
    }

    void onMTUChange(uint16_t MTU, ble_gap_conn_desc* desc) override {
        // Refresh the handle from the event rather than assuming the connect
        // callback already ran: this event can arrive first.
        if (desc != nullptr) {
            bleConnHandle = desc->conn_handle;
        }

        if (!LOG_MTU_DIAGNOSTICS) {
            return;
        }

        const uint16_t live = currentMtu();

        Serial.print("MTU negotiated: ");
        Serial.println(MTU);
        Serial.print("MTU usable notification payload: ");
        Serial.print(usablePayloadBytes(live));
        Serial.println(" bytes");

        // The event value and the live read should agree. If they ever do not,
        // the live value is authoritative and the discrepancy is worth seeing.
        if (live != MTU) {
            Serial.print("MTU NOTE: event reported ");
            Serial.print(MTU);
            Serial.print(" but the stack reports ");
            Serial.print(live);
            Serial.println("; using the stack value");
        }

        if ((live > 0) && (live < BLE_PREFERRED_MTU)) {
            Serial.print("MTU WARNING: peer granted less than the requested ");
            Serial.println(BLE_PREFERRED_MTU);
        }

        reportFitAgainstLargestSeen();
    }

    void onDisconnect(NimBLEServer* server) override {
        (void)server;
        bleClientConnected = false;
        bleClientSubscribed = false;
        bleConnHandle = BLE_CONN_HANDLE_INVALID;
        Serial.println("BLE client disconnected");
        NimBLEDevice::startAdvertising();
    }

private:
    void markConnected() {
        bleClientConnected = true;
        bleClientSubscribed = false;
        bleConnectedAtMs = millis();
    }

    void reportFitAgainstLargestSeen() {
        const uint16_t usable = currentUsablePayloadBytes();

        // Says nothing when the MTU is unknown, so an unknown value cannot be
        // mistaken for a failure.
        if ((largestPayloadSeen == 0) || (usable == 0)) {
            return;
        }

        Serial.print("MTU headroom: largest alert so far ");
        Serial.print(largestPayloadSeen);
        Serial.print(" bytes vs ");
        Serial.print(usable);
        Serial.println(" usable");

        if (largestPayloadSeen > usable) {
            Serial.println("MTU FAIL: alerts already exceed the usable payload");
        }
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

    // Available to currentMtu() even if a callback runs before the connect
    // overload that would otherwise set it.
    bleServer = server;

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

// TEMPORARY MTU DIAGNOSTIC. Reports the encoded size against the negotiated
// MTU so an oversized alert is visible on the console instead of failing
// silently at the BLE layer.
void logPayloadSize(size_t length) {
    if (length > largestPayloadSeen) {
        largestPayloadSeen = length;
    }

    Serial.print("CBOR payload: ");
    Serial.print(length);
    Serial.print(" bytes (largest so far ");
    Serial.print(largestPayloadSeen);
    Serial.print(")");

    // Live read at send time. This is the fix: the old code used a cached
    // value that could still hold the pre-negotiation default while the link
    // was already running at the negotiated MTU.
    const uint16_t mtu = currentMtu();

    if (mtu == 0) {
        Serial.println(" [MTU unknown, no active connection]");
        return;
    }

    const uint16_t usable = usablePayloadBytes(mtu);

    Serial.print(" [MTU ");
    Serial.print(mtu);
    Serial.print(", usable ");
    Serial.print(usable);
    Serial.println("]");

    if (length > usable) {
        Serial.print("MTU FAIL: payload exceeds usable notification size by ");
        Serial.print(length - usable);
        Serial.println(" bytes; the watch will see a truncated or dropped packet");
    }
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

    if (LOG_MTU_DIAGNOSTICS) {
        logPayloadSize(length);
    }

    if (alertCharacteristic == nullptr) {
        return;
    }

    // Keeps the most recent alert readable so a reconnecting watch can recover
    // current state without waiting for the next notification.
    alertCharacteristic->setValue(payloadBuffer, length);

    if (bleClientConnected && bleClientSubscribed && ((millis() - bleConnectedAtMs) >= 1000)) {
        alertCharacteristic->notify();

        Serial.print("notify sent: ");
        Serial.print(length);
        Serial.println(" bytes");

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
