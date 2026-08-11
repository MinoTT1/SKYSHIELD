#include <Arduino.h>
#include <NimBLEDevice.h>
#include <stdarg.h>

#include "IDetectorAdapter.h"
#include "MockAlertProvider.h"
#include "SerialInjectAdapter.h"
#include "DW01Adapter.h"
#include "SkyShieldCodec.h"
#include "TTSKW07Adapter.h"

namespace {

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

enum DetectorSelection : uint8_t {
    // Live Tatusky TTSKW07 on a hardware UART.
    DETECTOR_TTSKW07 = 0,
    // Tatusky DW01, the TTSKW07's replacement. Parser and adapter are built and
    // contract-tested but have NEVER seen the physical device. The UART pins
    // below are placeholders, and if the DW01 turns out to connect over BLE the
    // adapter is re-pointed while DW01Parser.h stays as it is.
    DETECTOR_DW01 = 3,
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

// The BLE default ATT MTU before any exchange: 23, giving 20 usable bytes.
// Seeing this at send time means negotiation never happened.
const uint16_t BLE_DEFAULT_MTU = 23;

// ----------------------------- MTU DIAGNOSTICS -----------------------------
// Verbose bench instrumentation: the per-packet size line, the CBOR hex dump,
// the pre-negotiation MTU snapshot and the headroom report. Serial-logging
// only; it does not change what is transmitted.
//
// Off by default now that MTU 185 is confirmed on Enduro 2 hardware. The hex
// dump alone is ~96 characters per alert, which on USB CDC is enough to crowd
// out the lines that matter.
//
// Deliberately NOT gated by this flag, because they are what make a field
// failure diagnosable:
//   - "MTU negotiated" once per connection, and its absence when negotiation
//     never happens
//   - "MTU FAIL" when a payload exceeds the usable notification size
//   - "MTU NOTE" when the event value and the stack disagree
//   - connect/subscribe/disconnect lines carrying conn_handle
//
// Set to true for bring-up of a new watch model or a new detector.
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
const bool LOG_MTU_DIAGNOSTICS = false;

// --------------------------- LATENCY INSTRUMENTATION -----------------------
// Reports the bridge-side segments of the alert path. Every number printed is
// a measured delta between two millis() reads on THIS device's clock; nothing
// is estimated, defaulted or inferred.
//
// Segments, using the naming in docs/latency-measurement.md:
//
//   A  detector -> core   raw line in hand until normalization finished.
//                         Measured by the adapter and carried as
//                         detector_latency_ms. Only meaningful with a
//                         physically connected detector; reported as "n/a"
//                         when the source did not measure it.
//   B  core -> BLE TX     normalization finished until handed to notify().
//   A+B                   total time the alert spent inside the bridge.
//
// Segment C (BLE TX -> watch) is NOT reported here and cannot be: it spans two
// unsynchronized clocks. See docs/latency-measurement.md.
const bool LOG_LATENCY = true;

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

// Set by onMTUChange. Proves whether the MTU exchange was actually observed,
// as opposed to the link silently staying at the 23-byte default.
bool mtuExchangeObserved = false;

// Counts connections since boot. A disconnect/reconnect is normal operation on
// this product, so each session is numbered in the log to make it obvious which
// connection a later line belongs to.
uint32_t bleSessionCount = 0;

// How long to wait after subscribe for MTU negotiation to settle before
// sending the first notification. The central normally drives the exchange
// immediately after connecting; sending before it completes would push the
// first alert out at the default MTU.
const uint32_t MTU_SETTLE_WAIT_MS = 1500;

uint32_t bleSubscribedAtMs = 0;
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Serial logging
// ---------------------------------------------------------------------------
//
// The board runs USB CDC serial (ARDUINO_USB_CDC_ON_BOOT=1). Emitting a line
// as a sequence of Serial.print() calls let the CDC TX buffer overrun, which
// DROPS bytes rather than blocking, producing spliced fragments like
// "BLE c23185" in the log. Diagnostics that cannot be read are worse than
// none: a corrupted line was misread as a successful MTU negotiation.
//
// Every line is now formatted into one buffer and written with a single
// println followed by flush. The mutex keeps the NimBLE host task and the
// Arduino loop task from writing at the same time, and flush throttles the
// producer so the CDC buffer cannot overrun.

SemaphoreHandle_t logMutex = nullptr;

void logLine(const char* format, ...) {
    char buffer[192];

    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    if (logMutex != nullptr) {
        xSemaphoreTake(logMutex, portMAX_DELAY);
    }

    Serial.println(buffer);
    Serial.flush();

    if (logMutex != nullptr) {
        xSemaphoreGive(logMutex);
    }
}
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

TTSKW07Adapter ttskw07Adapter(Serial1, TTSKW07_RX_PIN, TTSKW07_TX_PIN);
// Shares the UART with the TTSKW07: only one detector is ever selected.
DW01Adapter dw01Adapter(Serial1, TTSKW07_RX_PIN, TTSKW07_TX_PIN);
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

// Asks the peer to raise the ATT MTU.
//
// MTU exchange is normally driven by the central, and a central that never
// initiates one leaves the link at the 23-byte default forever. Either side
// may send the request, so the bridge asks rather than waiting indefinitely.
// Harmless if the peer already exchanged: NimBLE reports BLE_HS_EALREADY.
void requestMtuExchange() {
    if (bleConnHandle == BLE_CONN_HANDLE_INVALID) {
        return;
    }

    const int status = ble_gattc_exchange_mtu(bleConnHandle, nullptr, nullptr);

    if (status == 0) {
        logLine("MTU exchange requested by bridge on handle %u", bleConnHandle);
        return;
    }

    logLine("MTU exchange request returned %d (already exchanged or unsupported)", status);
}

class SkyShieldServerCallbacks : public NimBLEServerCallbacks {
public:
    // NimBLE invokes both onConnect overloads. This one has no connection
    // descriptor, so it only marks state; the descriptor overload owns the
    // handle and the MTU logging.
    void onConnect(NimBLEServer* server) override {
        (void)server;
        markConnected();
    }

    void onConnect(NimBLEServer* server, ble_gap_conn_desc* desc) override {
        markConnected();

        if ((server != nullptr) && (desc != nullptr)) {
            bleServer = server;
            bleConnHandle = desc->conn_handle;
        }

        bleSessionCount += 1;

        logLine("BLE client connected (session %u, conn_handle=%u)",
                (unsigned)bleSessionCount, bleConnHandle);

        if (LOG_MTU_DIAGNOSTICS) {
            // Reads the same live source the send path uses, so these two lines
            // cannot disagree. Normally still 23 here, because MTU exchange has
            // not happened yet at connect time.
            logLine("MTU at connect: %u (requested %u) handle=%u",
                    currentMtu(), BLE_PREFERRED_MTU, bleConnHandle);
        }

        // Do not wait on the central to start the exchange.
        requestMtuExchange();
    }

    void onMTUChange(uint16_t MTU, ble_gap_conn_desc* desc) override {
        // Refresh the handle from the event rather than assuming the connect
        // callback already ran: this event can arrive first.
        if (desc != nullptr) {
            bleConnHandle = desc->conn_handle;
        }

        mtuExchangeObserved = true;

        const uint16_t live = currentMtu();

        // Permanent, one line per connection. Confirms the exchange happened and
        // records the payload budget the link actually has. Its ABSENCE from a
        // log is the signal that negotiation never occurred, which is exactly
        // how the stuck-at-23 fault was finally identified.
        logLine("MTU negotiated: %u (usable %u) handle=%u session=%u",
                live, usablePayloadBytes(live), bleConnHandle, (unsigned)bleSessionCount);

        // The event value and the live read should agree. A disagreement means
        // one of them is lying about the link, which is worth seeing even in a
        // quiet build.
        if (live != MTU) {
            logLine("MTU NOTE: event reported %u but the stack reports %u; using the stack value",
                    MTU, live);
        }

        if (!LOG_MTU_DIAGNOSTICS) {
            return;
        }

        if ((live > 0) && (live < BLE_PREFERRED_MTU)) {
            logLine("MTU WARNING: peer granted %u, less than the requested %u",
                    live, BLE_PREFERRED_MTU);
        }

        reportFitAgainstLargestSeen();
    }

    void onDisconnect(NimBLEServer* server) override {
        (void)server;
        handleDisconnect(-1);
    }

    // Overload carrying the descriptor, so the connection handle is available.
    // Overriding both keeps this symmetric with onConnect: relying on a single
    // overload would leave a stale handle behind if the stack only invoked the
    // other one.
    void onDisconnect(NimBLEServer* server, ble_gap_conn_desc* desc) override {
        (void)server;
        handleDisconnect((desc != nullptr) ? static_cast<int>(desc->conn_handle) : -1);
    }

private:
    // Idempotent: NimBLE invokes both disconnect overloads, and the second call
    // must not double-log or re-advertise.
    void handleDisconnect(int handle) {
        if (!bleClientConnected && (bleConnHandle == BLE_CONN_HANDLE_INVALID)) {
            return;
        }

        logLine("BLE client disconnected (session %u, handle=%d, mtu_was_negotiated=%s)",
                (unsigned)bleSessionCount, handle, mtuExchangeObserved ? "yes" : "no");

        bleClientConnected = false;
        bleClientSubscribed = false;

        // Cleared so currentMtu() cannot read a dead connection. A stale handle
        // here would make the send path compute the payload budget from the
        // wrong link, which is the failure this area already had once.
        bleConnHandle = BLE_CONN_HANDLE_INVALID;

        // Reset so the next connection must negotiate again from scratch. MTU
        // does NOT carry across connections.
        mtuExchangeObserved = false;
        bleSubscribedAtMs = 0;

        restartAdvertising();
    }

    // Advertising must come back or the bridge is invisible forever. The result
    // is checked rather than assumed, because a silent failure here looks
    // exactly like the watch being out of range.
    void restartAdvertising() {
        if (NimBLEDevice::startAdvertising()) {
            logLine("BLE advertising restarted, waiting for reconnect");
            return;
        }

        logLine("BLE ADVERTISING RESTART FAILED, retrying");

        delay(50);

        if (NimBLEDevice::startAdvertising()) {
            logLine("BLE advertising restarted on retry");
            return;
        }

        logLine("BLE ADVERTISING STILL DOWN: bridge is undiscoverable");
    }

    void markConnected() {
        bleClientConnected = true;
        bleClientSubscribed = false;
        bleConnectedAtMs = millis();
        bleSubscribedAtMs = 0;
    }

    void reportFitAgainstLargestSeen() {
        const uint16_t usable = currentUsablePayloadBytes();

        // Says nothing when the MTU is unknown, so an unknown value cannot be
        // mistaken for a failure.
        if ((largestPayloadSeen == 0) || (usable == 0)) {
            return;
        }

        logLine("MTU headroom: largest alert so far %u bytes vs %u usable",
                (unsigned)largestPayloadSeen, usable);

        if (largestPayloadSeen > usable) {
            logLine("MTU FAIL: alerts already exceed the usable payload");
        }
    }
};

class SkyShieldAlertCallbacks : public NimBLECharacteristicCallbacks {
public:
    void onSubscribe(NimBLECharacteristic* characteristic, ble_gap_conn_desc* desc, uint16_t subValue) override {
        (void)characteristic;
        bleClientSubscribed = subValue > 0;

        // Subscribe carries a valid descriptor, so use it as a backstop for the
        // handle in case the connect overload was missed.
        if ((desc != nullptr) && (bleConnHandle == BLE_CONN_HANDLE_INVALID)) {
            bleConnHandle = desc->conn_handle;
        }

        if (!bleClientSubscribed) {
            logLine("BLE client unsubscribed");
            return;
        }

        bleSubscribedAtMs = millis();

        logLine("BLE client subscribed, conn_handle=%u mtu=%u",
                (desc != nullptr) ? desc->conn_handle : bleConnHandle, currentMtu());

        // Last chance to raise the MTU before notifications start flowing.
        requestMtuExchange();
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
    logLine("BLE advertising as SKYSHIELD-BRIDGE");
}

// ---------------------------------------------------------------------------
// Publishing
// ---------------------------------------------------------------------------

void printAlertSummary(const skyshield::Alert& alert) {
    using namespace skyshield;

    char confidence[8];

    if (alert.hasConfidence) {
        snprintf(confidence, sizeof(confidence), "%u", alert.confidence);
    } else {
        snprintf(confidence, sizeof(confidence), "none");
    }

    char latency[24];

    if (alert.hasDetectorLatency) {
        snprintf(latency, sizeof(latency), " detector_to_core=%ums",
                 (unsigned)alert.detectorLatencyMs);
    } else {
        latency[0] = '\0';
    }

    logLine("ALERT kind=%s sensor=%s threat=%s severity=%s band=%s strength=%s "
            "confidence=%s class=%s seq=%u t=%u%s",
            alertKindName(alert.alertKind), sensorTypeName(alert.sensorType),
            threatName(alert.threat), severityName(alert.severity),
            bandName(alert.band), distanceName(alert.distance), confidence,
            alert.hasDroneClass ? alert.droneClass : "-",
            (unsigned)alert.sequence, (unsigned)alert.timestampMs, latency);
}

void printPayloadHex(const uint8_t* payload, size_t length) {
    // Built as one string: MAX_PAYLOAD_BYTES is 180, so the hex fits well
    // inside the line buffer and cannot be split across CDC writes.
    char hex[(skyshield::MAX_PAYLOAD_BYTES * 2) + 1];
    size_t offset = 0;

    for (size_t i = 0; (i < length) && ((offset + 2) < sizeof(hex)); i += 1) {
        offset += snprintf(&hex[offset], sizeof(hex) - offset, "%02X", payload[i]);
    }

    hex[offset] = '\0';

    logLine("BLE TX CBOR len=%u bytes=%s", (unsigned)length, hex);
}

// TEMPORARY MTU DIAGNOSTIC. Reports the encoded size against the negotiated
// MTU so an oversized alert is visible on the console instead of failing
// silently at the BLE layer.
void logPayloadSize(size_t length) {
    // Live read at send time, with the handle it was read from, so a wrong or
    // stale handle is visible rather than being inferred from a bare 23.
    const uint16_t mtu = currentMtu();

    if (mtu == 0) {
        logLine("CBOR payload: %u bytes (largest so far %u) [MTU unknown, no active connection]",
                (unsigned)length, (unsigned)largestPayloadSeen);
        return;
    }

    logLine("CBOR payload: %u bytes (largest so far %u) [MTU %u, usable %u, handle=%u, "
            "exchange_seen=%s]",
            (unsigned)length, (unsigned)largestPayloadSeen, mtu, usablePayloadBytes(mtu),
            bleConnHandle, mtuExchangeObserved ? "yes" : "no");
}

// PERMANENT correctness guard, deliberately not behind LOG_MTU_DIAGNOSTICS.
//
// An oversized notification is silently truncated by the BLE stack and decodes
// on the watch as a parse error with no indication of why. This is the one line
// that explains it, so it must survive with diagnostics switched off. It costs
// nothing when everything fits, because it only logs on failure.
void warnIfPayloadExceedsMtu(size_t length) {
    const uint16_t mtu = currentMtu();

    // Unknown MTU is not a failure and must never be reported as one.
    if (mtu == 0) {
        return;
    }

    const uint16_t usable = usablePayloadBytes(mtu);

    if (length <= usable) {
        return;
    }

    logLine("MTU FAIL: payload %u bytes exceeds usable notification size %u by %u; "
            "the watch will see a truncated or dropped packet",
            (unsigned)length, usable, (unsigned)(length - usable));

    if (!mtuExchangeObserved) {
        logLine("MTU CAUSE: no MTU exchange was observed on this link, so it is still "
                "at the %u-byte default", (unsigned)mtu);
    }
}

// True once the MTU is settled, or once waiting for it has timed out.
//
// The central drives MTU exchange, so the first notification must not race
// ahead of it: a notify sent before the exchange completes goes out at the
// default MTU and is truncated regardless of what is negotiated a moment
// later. After the timeout it sends anyway, because silently never sending
// would be a worse failure than a visible oversized one.
bool mtuSettledOrTimedOut() {
    if (mtuExchangeObserved) {
        return true;
    }

    if (currentMtu() > BLE_DEFAULT_MTU) {
        return true;
    }

    if (bleSubscribedAtMs == 0) {
        return false;
    }

    return (millis() - bleSubscribedAtMs) >= MTU_SETTLE_WAIT_MS;
}

// Reports the bridge-side latency segments for one alert.
//
// Both endpoints of every value printed here come from this device's millis()
// clock, so each is a valid measured duration. Nothing is estimated. Segment A
// is printed as "n/a" rather than 0 when the source did not measure an ingest
// moment, because a source with no detector has no detector latency.
void logAlertLatency(const skyshield::Alert& alert, uint32_t normalizedMs, uint32_t txMs) {
    if (!LOG_LATENCY) {
        return;
    }

    // Unsigned arithmetic, so a millis() wrap at ~49.7 days still yields the
    // correct elapsed time.
    const uint32_t segmentB = txMs - normalizedMs;

    if (alert.hasDetectorLatency) {
        logLine("LATENCY seq=%u A_detector_to_core=%ums B_core_to_tx=%ums "
                "A+B_in_bridge=%ums [single ESP32 clock, measured]",
                (unsigned)alert.sequence, (unsigned)alert.detectorLatencyMs,
                (unsigned)segmentB, (unsigned)(alert.detectorLatencyMs + segmentB));
    } else {
        logLine("LATENCY seq=%u A_detector_to_core=n/a (source '%s' has no detector ingest) "
                "B_core_to_tx=%ums [single ESP32 clock, measured]",
                (unsigned)alert.sequence, activeSourceLabel(), (unsigned)segmentB);
    }

    // Stated explicitly every time so the absence of a number for C is read as
    // "not measurable this way" rather than as an oversight.
    logLine("LATENCY seq=%u C_tx_to_watch=unmeasured (cross-clock) core_tx_ms=%u",
            (unsigned)alert.sequence, (unsigned)txMs);
}

// Encodes and transmits one alert. Refuses to transmit a packet that failed to
// encode rather than sending a truncated map, which would decode to a
// plausible-but-wrong alert.
void publishAlert(const skyshield::Alert& alert) {
    printAlertSummary(alert);

    const bool notifyPossible =
        (alertCharacteristic != nullptr) && bleClientConnected && bleClientSubscribed;

    // Checked BEFORE stamping t_tx. Deferring after the stamp would ship a
    // timestamp up to MTU_SETTLE_WAIT_MS stale and corrupt the measurement.
    if (notifyPossible && !mtuSettledOrTimedOut()) {
        logLine("notify deferred: waiting for MTU exchange (currently %u)", currentMtu());
        return;
    }

    // Latency point (b): normalization is done and the alert is about to go on
    // the wire. timestamp_ms carries this moment, which is what
    // docs/wire-protocol.md specifies ("immediately before BLE transmission")
    // and what the watch needs in order to reason about segment C at all.
    skyshield::Alert txAlert = alert;
    const uint32_t normalizedMs = alert.timestampMs;
    const uint32_t txMs = millis();
    txAlert.timestampMs = txMs;

    const size_t length = skyshield::encodeAlert(txAlert, payloadBuffer, sizeof(payloadBuffer));

    if (length == 0) {
        logLine("ENCODE FAILED: alert not transmitted");
        return;
    }

    if (length > largestPayloadSeen) {
        largestPayloadSeen = length;
    }

    if (LOG_MTU_DIAGNOSTICS) {
        printPayloadHex(payloadBuffer, length);
        logPayloadSize(length);
    }

    warnIfPayloadExceedsMtu(length);

    if (alertCharacteristic == nullptr) {
        return;
    }

    // Keeps the most recent alert readable so a reconnecting watch can recover
    // current state without waiting for the next notification.
    alertCharacteristic->setValue(payloadBuffer, length);

    if (!notifyPossible) {
        sequence += 1;
        return;
    }

    alertCharacteristic->notify();

    logLine("notify sent: %u bytes", (unsigned)length);
    logAlertLatency(txAlert, normalizedMs, txMs);

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
        logLine("%s", mockAlerts.priorityTestBlockLabel(elapsedMs));
        mockAlerts.priorityTestAlert(elapsedMs, alert, millis(), sequence);
    } else {
        mockAlerts.next(alert, millis(), sequence);
    }

    publishAlert(alert);
}

void selectDetector() {
    switch (ACTIVE_DETECTOR) {
        case DETECTOR_DW01:
            detector = &dw01Adapter;
            break;

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
        logLine("DETECTOR FAILED TO START: %s", detector->name());
        detector = nullptr;
    }
}

}  // namespace

void setup() {
    Serial.begin(115200);

    // USB CDC needs a moment before the host is ready; without it the first
    // lines are lost.
    delay(400);

    // Created before the first logLine so no output is unserialized.
    logMutex = xSemaphoreCreateMutex();

    logLine("SKYSHIELD ESP32 Bridge starting...");
    logLine("PROTOCOL VERSION: %u", (unsigned)skyshield::PROTOCOL_VERSION);

    initBle();
    selectDetector();

    logLine("ACTIVE SOURCE: %s", activeSourceLabel());

    if (usingMockProvider()) {
        mockStartedAtMs = millis();
        lastMockMs = millis();

        skyshield::Alert alert;

        if (PRIORITY_TEST_MODE) {
            logLine("PRIORITY TEST MODE: ON");
            logLine("%s", mockAlerts.priorityTestBlockLabel(0));
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
