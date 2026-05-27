using Toybox.BluetoothLowEnergy as Ble;
using Toybox.StringUtil as StringUtil;
import Toybox.System;

const BLE_STATE_SCANNING = "SCANNING";
const BLE_STATE_CONNECTING = "CONNECTING";
const BLE_STATE_CONNECTED = "CONNECTED";
const BLE_STATE_DISCONNECTED = "DISCONNECTED";
const BLE_STATE_SIGNAL_LOST = "SIGNAL_LOST";
const SKYSHIELD_BLE_DEVICE_NAME = "SKYSHIELD-BRIDGE";
const SKYSHIELD_BLE_SERVICE_UUID = "9f4d0001-7c31-4f9b-9a4b-8f4c0f000001";
const SKYSHIELD_BLE_ALERT_CHARACTERISTIC_UUID = "9f4d0002-7c31-4f9b-9a4b-8f4c0f000001";
const BLE_STATUS_OFF = "BLE OFF";
const BLE_STATUS_SCAN = "SCAN";
const BLE_STATUS_FOUND = "FOUND";
const BLE_STATUS_CONNECT = "CONNECT";
const BLE_STATUS_SUBSCRIBE = "SUBSCRIBE";
const BLE_STATUS_RX = "RX";
const BLE_STATUS_SUB_WAIT = "NOTIFY WAIT";
const BLE_DIAG_INIT = "BLE INIT";
const BLE_DIAG_REG = "BLE REG";
const BLE_DIAG_SCAN = "BLE SCAN";
const BLE_DIAG_FOUND = "BLE FOUND";
const BLE_DIAG_CONN = "BLE CONN";
const BLE_DIAG_SVC = "BLE SVC";
const BLE_DIAG_CHAR = "BLE CHAR";
const BLE_DIAG_SUB = "BLE SUB";
const BLE_DIAG_SUB_WAIT = "NOTIFY WAIT";
const BLE_DIAG_RX = "RX";
const BLE_STAGE_SCAN = "SCAN";
const BLE_STAGE_REG = "REG";
const BLE_STAGE_FOUND = "FOUND";
const BLE_STAGE_CONN = "CONN";
const BLE_STAGE_SVC = "SVC";
const BLE_STAGE_CHAR = "CHAR";
const BLE_STAGE_SUB = "SUB";
const BLE_STAGE_RX = "RX";
const BLE_STAGE_PARSE = "PARSE";
const BLE_ERR_SCAN = "ERR SCAN";
const BLE_ERR_FOUND = "ERR FOUND";
const BLE_ERR_CONN = "ERR CONN";
const BLE_ERR_SVC = "ERR SVC";
const BLE_ERR_CHAR = "ERR CHAR";
const BLE_ERR_SUB = "ERR SUB";
const BLE_ERR_RX = "NOTIFY ERR";
const BLE_ERR_RX_TIMEOUT = "NOTIFY ERR";
const BLE_ERR_DISC = "SIGNAL LOST";
const BLE_ERR_PARSE = "ERR PARSE";
const BLE_STAGE_TIMEOUT_MS = 20000;

class BleAlertSource extends AlertSource {
    var _latestAlert;
    var _hasUnreadAlert;
    var _state;
    var _enabled;
    var _delegate;
    var _device;
    var _alertCharacteristic;
    var _serviceUuid;
    var _alertCharacteristicUuid;
    var _cccdUuid;
    var _diagState;
    var _bleStatus;
    var _diagElapsedMs;
    var _scanTimeoutLogged;
    var _rxTimeoutLogged;
    var _lastBleStage;
    var _profileRegistered;
    var isScanning;
    var isConnecting;
    var isConnected;
    var isSubscribed;
    var hasEverFoundPeripheral;
    var hasEverConnected;
    var hasEverSubscribed;
    var _uptimeMs;
    var _connectStartedAtMs;
    var _connectedAtMs;
    var _subscribeStartedAtMs;
    var _subscribedAtMs;
    var _disconnectedAtMs;
    var _lastBridgeActivityMs;
    var lastSubscribeMs;
    var lastRxMs;
    var explicitDisconnectSeen;
    var _lastRawPayload;
    var _lastParseOk;
    var _lastParsedSummary;
    var _hasLatestAlert;
    var _lastPayloadLength;
    var _lastDirectParseResult;

    function initialize() {
        AlertSource.initialize();
        _latestAlert = null;
        _hasUnreadAlert = false;
        _state = BLE_STATE_DISCONNECTED;
        _enabled = false;
        _delegate = null;
        _device = null;
        _alertCharacteristic = null;
        _serviceUuid = null;
        _alertCharacteristicUuid = null;
        _cccdUuid = null;
        _diagState = BLE_DIAG_SCAN;
        _bleStatus = BLE_STATUS_OFF;
        _diagElapsedMs = 0;
        _scanTimeoutLogged = false;
        _rxTimeoutLogged = false;
        _lastBleStage = BLE_STAGE_SCAN;
        _profileRegistered = false;
        isScanning = false;
        isConnecting = false;
        isConnected = false;
        isSubscribed = false;
        hasEverFoundPeripheral = false;
        hasEverConnected = false;
        hasEverSubscribed = false;
        _uptimeMs = 0;
        _connectStartedAtMs = 0;
        _connectedAtMs = 0;
        _subscribeStartedAtMs = 0;
        _subscribedAtMs = 0;
        _disconnectedAtMs = 0;
        _lastBridgeActivityMs = 0;
        lastSubscribeMs = 0;
        lastRxMs = 0;
        explicitDisconnectSeen = false;
        _lastRawPayload = "";
        _lastParseOk = false;
        _lastParsedSummary = "";
        _hasLatestAlert = false;
        _lastPayloadLength = 0;
        _lastDirectParseResult = "";
    }

    function start() {
        _enabled = true;
        log("init");
        setDiagnosticState(BLE_DIAG_INIT, BLE_STATUS_OFF);

        try {
            _serviceUuid = Ble.stringToUuid(SKYSHIELD_BLE_SERVICE_UUID);
            _alertCharacteristicUuid = Ble.stringToUuid(SKYSHIELD_BLE_ALERT_CHARACTERISTIC_UUID);
            _cccdUuid = Ble.cccdUuid();

            _delegate = new SkyShieldBleDelegate(self);

            if (_delegate == null) {
                setScanError("delegate creation failed");
                return;
            }

            Ble.setDelegate(_delegate);
            log("delegate set");
            registerSkyShieldProfile();
            startScan();
        } catch (ex) {
            System.println("SKYSHIELD BLE unavailable.");
            log("scan failed: " + ex);
            setScanError("BLE unavailable: " + ex);
        }
    }

    function stop() {
        _enabled = false;

        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        } catch (ex) {
            log("stop warning: " + ex);
        }

        setLifecycleFlags(false, false, false, false, "stop");
        setBleState(BLE_STATE_DISCONNECTED, BLE_STATUS_OFF, BLE_STATUS_OFF);
        log("stopped");
    }

    function tick(elapsedMs) {
        _uptimeMs += elapsedMs;
        _diagElapsedMs += elapsedMs;

        if ((_diagState == BLE_DIAG_SCAN) && (_diagElapsedMs >= BLE_STAGE_TIMEOUT_MS) && !_scanTimeoutLogged) {
            _scanTimeoutLogged = true;
            log("scan timeout");
        }

        if (isSubscribed && (lastRxMs == 0) && ((lastSubscribeMs > 0) && ((_uptimeMs - lastSubscribeMs) >= BLE_STAGE_TIMEOUT_MS)) && !_rxTimeoutLogged) {
            _rxTimeoutLogged = true;
            log("subscribed with no detector alerts; staying MONITOR");
        }

        if (((_diagState == BLE_DIAG_CONN) || (_diagState == BLE_DIAG_SVC) || (_diagState == BLE_DIAG_CHAR) || (_diagState == BLE_DIAG_SUB)) &&
            (_diagElapsedMs >= BLE_STAGE_TIMEOUT_MS) && !_rxTimeoutLogged) {
            _rxTimeoutLogged = true;

            if (_diagState == BLE_DIAG_SUB) {
                log("NOTIFY ERR timeout");
                setRxTimeoutError("notification callback timeout after subscribe");
            } else {
                setBleError(_lastBleStage, "BLE pipeline timeout before notifications");
            }
        }
    }

    function getNextAlert() {
        if (!_enabled) {
            return null;
        }

        _hasUnreadAlert = false;
        return _latestAlert;
    }

    function getLatestAlert() {
        if (!_enabled) {
            return null;
        }

        if (!_hasLatestAlert || (_latestAlert == null)) {
            return null;
        }

        return _latestAlert;
    }

    function hasLatestAlert() {
        return _hasLatestAlert && (_latestAlert != null);
    }

    function hasActiveBleAlert() {
        return hasLatestAlert();
    }

    function hasValidBleAlert() {
        var hasAlert = _hasLatestAlert && (_latestAlert != null);
        System.println("SKYSHIELD BLE hasValidBleAlert=" + boolText(hasAlert));
        return hasAlert;
    }

    function getLastRawPayload() {
        return _lastRawPayload;
    }

    function wasLastParseOk() {
        return _lastParseOk;
    }

    function getLastParsedSummary() {
        return _lastParsedSummary;
    }

    function getLastPayloadLength() {
        return _lastPayloadLength;
    }

    function getLastDirectParseResult() {
        return _lastDirectParseResult;
    }

    function getState() {
        return _state;
    }

    function getDiagnosticState() {
        return _diagState;
    }

    function getBleStatus() {
        return _bleStatus;
    }

    function getLastRxAgeMs() {
        if (lastRxMs == 0) {
            return _uptimeMs;
        }

        return _uptimeMs - lastRxMs;
    }

    function getBridgeActivityAgeMs() {
        if (_lastBridgeActivityMs == 0) {
            return _uptimeMs;
        }

        return _uptimeMs - _lastBridgeActivityMs;
    }

    function hasConnection() {
        return _state == BLE_STATE_CONNECTED;
    }

    function isLinkAlive() {
        if (explicitDisconnectSeen || _state == BLE_STATE_SIGNAL_LOST) {
            return false;
        }

        return isConnected ||
            isSubscribed ||
            _state == BLE_STATE_CONNECTED ||
            _diagState == BLE_DIAG_SUB ||
            _diagState == BLE_DIAG_SUB_WAIT ||
            _diagState == BLE_DIAG_RX;
    }

    function hasExplicitDisconnect() {
        return explicitDisconnectSeen || _state == BLE_STATE_SIGNAL_LOST;
    }

    function markBridgeActivity(reason) {
        _lastBridgeActivityMs = _uptimeMs;
        log("bridge activity: " + reason);
    }

    function registerSkyShieldProfile() {
        if ((_serviceUuid == null) || (_alertCharacteristicUuid == null) || (_cccdUuid == null)) {
            log("profile registration skipped, UUID unavailable");
            return;
        }

        setDiagnosticState(BLE_DIAG_REG, BLE_STATUS_OFF);

        var profile = {
            :uuid => _serviceUuid,
            :characteristics => [
                {
                    :uuid => _alertCharacteristicUuid,
                    :descriptors => [ _cccdUuid ]
                }
            ]
        };

        try {
            Ble.registerProfile(profile);
            log("profile registration requested");
        } catch (ex) {
            log("profile registration failed: " + ex);
        }
    }

    function startScan() {
        if (!_enabled) {
            return;
        }

        if (isScanning) {
            log("scan start ignored, already scanning");
            return;
        }

        if (isConnecting) {
            log("scan start ignored, connecting");
            return;
        }

        if (isConnected) {
            log("scan start ignored, connected");
            return;
        }

        if (isSubscribed) {
            log("scan start ignored, subscribed");
            return;
        }

        setLifecycleFlags(true, false, false, false, "scan start");
        setBleState(BLE_STATE_SCANNING, BLE_DIAG_SCAN, BLE_STATUS_SCAN);
        log("scan requested");

        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        } catch (ex) {
            setLifecycleFlags(false, false, false, false, "scan start failed");
            log("scan failed: " + ex);
            setScanError("scan failed: " + ex);
        }
    }

    function stopScan() {
        if (!isScanning) {
            log("scan stop ignored, not scanning");
            return;
        }

        setLifecycleFlags(false, isConnecting, isConnected, isSubscribed, "scan stop");

        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
            log("scan stop requested");
        } catch (ex) {
            log("scan stop warning: " + ex);
        }
    }

    function handleProfileRegister(uuid, status) {
        log("PROFILE callback entered");
        log("profile registered status=" + status);

        if (status == Ble.STATUS_SUCCESS) {
            _profileRegistered = true;
            log("profile registered");
            return;
        }

        log("profile registration failed status=" + status);
    }

    function handleScanStateChange(scanState, status) {
        log("SCAN callback entered");
        log("scan state=" + scanState + " status=" + status);

        if (!canProcessScanCallback()) {
            if (status != Ble.STATUS_SUCCESS) {
                setScanError("scan callback status=" + status);
            }
            return;
        }

        if (status != Ble.STATUS_SUCCESS) {
            log("scan failed: status=" + status);

            if (isScanning) {
                setLifecycleFlags(false, false, false, false, "scan failed callback");
                setScanError("scan failed status=" + status);
            } else {
                setScanError("scan failed while not scanning status=" + status);
            }

            return;
        }

        if (scanState == Ble.SCAN_STATE_SCANNING) {
            setLifecycleFlags(true, false, false, false, "scan started");
            log("scan started");
        }
    }

    function handleScanResults(scanResults) {
        log("SCAN callback entered");
        var result = scanResults.next();

        while (result != null) {
            logScanResult(result);

            if (isSkyShieldPeripheral(result)) {
                log("BLE matched SKYSHIELD peripheral");
                hasEverFoundPeripheral = true;
                log("ever found peripheral");
                setLifecycleFlags(false, false, false, false, "found peripheral");
                stopScanForConnect();
                setDiagnosticState(BLE_DIAG_FOUND, BLE_STATUS_FOUND);
                connectToScanResult(result);
                return;
            }

            result = scanResults.next();
        }
    }

    function logScanResult(scanResult) {
        var deviceName = scanResult.getDeviceName();

        if (deviceName == null) {
            log("BLE found peripheral name=<none>");
        } else {
            log("BLE found peripheral name=" + deviceName);
        }

        logAdvertisedServices(scanResult);
    }

    function logAdvertisedServices(scanResult) {
        var services = scanResult.getServiceUuids();

        if (services == null) {
            log("BLE advertised services <none>");
            return;
        }

        var serviceUuid = services.next();
        var sawService = false;

        while (serviceUuid != null) {
            sawService = true;
            log("BLE advertised services " + serviceUuid.toString());
            serviceUuid = services.next();
        }

        if (!sawService) {
            log("BLE advertised services <none>");
        }
    }

    function hasSkyShieldService(scanResult) {
        var services = scanResult.getServiceUuids();

        if (services == null) {
            return false;
        }

        var serviceUuid = services.next();

        while (serviceUuid != null) {
            if (serviceUuid.equals(_serviceUuid)) {
                return true;
            }

            serviceUuid = services.next();
        }

        return false;
    }

    function hasSkyShieldName(scanResult) {
        var deviceName = scanResult.getDeviceName();

        if (deviceName == null) {
            return false;
        }

        return deviceName == SKYSHIELD_BLE_DEVICE_NAME;
    }

    function isSkyShieldPeripheral(scanResult) {
        if (hasSkyShieldService(scanResult)) {
            log("BLE matched SKYSHIELD advertised service");
            return true;
        }

        if (hasSkyShieldName(scanResult)) {
            log("BLE matched SKYSHIELD local name");
            return true;
        }

        return false;
    }

    function connectToScanResult(scanResult) {
        hasEverConnected = true;
        explicitDisconnectSeen = false;
        _connectStartedAtMs = _uptimeMs;
        markBridgeActivity("connect start");
        log("ever connected");
        setLifecycleFlags(false, true, false, false, "connect start");
        setBleState(BLE_STATE_CONNECTING, BLE_DIAG_CONN, BLE_STATUS_CONNECT);
        log("BLE connecting");

        try {
            _device = Ble.pairDevice(scanResult);

            if (_device == null) {
                setLifecycleFlags(false, false, false, false, "connect failed");
                setBleError(BLE_STAGE_CONN, "pairDevice returned null");
            }
        } catch (ex) {
            setLifecycleFlags(false, false, false, false, "connect exception");
            setBleError(BLE_STAGE_CONN, "connect failed: " + ex);
        }
    }

    function handleConnectedStateChanged(device, state) {
        _device = device;

        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            log("CONNECTED callback entered");
            hasEverConnected = true;
            explicitDisconnectSeen = false;
            _connectedAtMs = _uptimeMs;
            markBridgeActivity("connected");
            setLifecycleFlags(false, false, true, false, "connected");
            setBleState(BLE_STATE_CONNECTED, BLE_DIAG_CONN, BLE_STATUS_CONNECT);
            log("onConnected");
            log("BLE connected");
            logTiming("CONNECT", _connectStartedAtMs, _connectedAtMs);
            discoverAlertCharacteristic(device);
            return;
        }

        _disconnectedAtMs = _uptimeMs;
        explicitDisconnectSeen = true;
        log("DISCONNECT callback entered");
        log("onDisconnected state=" + state);
        logDisconnectTiming();
        setLifecycleFlags(false, false, false, false, "disconnect");

        if (hasEverSubscribed || (_diagState == BLE_DIAG_SUB) || isSubscribed) {
            setDisconnectError("disconnected state=" + state);
        } else {
            setBleError(BLE_STAGE_CONN, "disconnected state=" + state);
        }

        _alertCharacteristic = null;
    }

    function discoverAlertCharacteristic(device) {
        log("SERVICE callback entered");

        if (device == null) {
            setBleError(BLE_STAGE_SVC, "service discovery skipped, device null");
            return;
        }

        var service = device.getService(_serviceUuid);

        if (service == null) {
            setBleError(BLE_STAGE_SVC, "service not discovered");
            return;
        }

        setDiagnosticState(BLE_DIAG_SVC, BLE_STATUS_CONNECT);
        markBridgeActivity("service discovered");
        log("service discovered");
        log("CHAR callback entered");

        _alertCharacteristic = service.getCharacteristic(_alertCharacteristicUuid);

        if (_alertCharacteristic == null) {
            setBleError(BLE_STAGE_CHAR, "characteristic not discovered");
            return;
        }

        setDiagnosticState(BLE_DIAG_CHAR, BLE_STATUS_CONNECT);
        markBridgeActivity("characteristic discovered");
        log("characteristic discovered");
        subscribeToAlertCharacteristic();
    }

    function subscribeToAlertCharacteristic() {
        hasEverSubscribed = true;
        _subscribeStartedAtMs = _uptimeMs;
        markBridgeActivity("subscribe start");
        log("ever subscribed");

        if (_alertCharacteristic == null) {
            setBleError(BLE_STAGE_SUB, "subscribe skipped, characteristic null");
            return;
        }

        var descriptor = _alertCharacteristic.getDescriptor(_cccdUuid);

        if (descriptor == null) {
            setBleError(BLE_STAGE_SUB, "cccd descriptor not discovered");
            return;
        }

        try {
            // Garmin calls onCharacteristicChanged() after notifications are enabled by writing [0x01,0x00] to CCCD 0x2902.
            log("CCCD uuid=0x2902 value=[1,0]");
            descriptor.requestWrite([1, 0]b);
            setDiagnosticState(BLE_DIAG_SUB, BLE_STATUS_SUBSCRIBE);
            log("subscribe requested");
        } catch (ex) {
            setBleError(BLE_STAGE_SUB, "subscribe failed: " + ex);
        }
    }

    function handleDescriptorWrite(descriptor, status) {
        log("SUBSCRIBE callback entered");

        if (!isAlertDescriptor(descriptor)) {
            setBleError(BLE_STAGE_SUB, "descriptor write was not for alert CCCD");
            return;
        }

        if (status == Ble.STATUS_SUCCESS) {
            hasEverSubscribed = true;
            _subscribedAtMs = _uptimeMs;
            lastSubscribeMs = _uptimeMs;
            lastRxMs = 0;
            markBridgeActivity("subscribed");
            setLifecycleFlags(false, false, true, true, "subscribed");
            setDiagnosticState(BLE_DIAG_SUB_WAIT, BLE_STATUS_SUB_WAIT);
            log("onSubscribeSuccess");
            log("BLE subscribed");
            log("subscribed waiting for notification callback");
            logTiming("CONNECT_START_TO_SUBSCRIBE", _connectStartedAtMs, _subscribedAtMs);
            logTiming("CONNECTED_TO_SUBSCRIBE", _connectedAtMs, _subscribedAtMs);
            return;
        }

        setBleError(BLE_STAGE_SUB, "subscribe status=" + status);
    }

    function handleCharacteristicChanged(characteristic, value) {
        log("NOTIFICATION callback entered");

        if (!isAlertCharacteristic(characteristic)) {
            log("notification ignored for non-alert characteristic");
            return;
        }

        lastRxMs = _uptimeMs;
        markBridgeActivity("notification");
        setLifecycleFlags(false, false, true, true, "rx packet");
        setDiagnosticState(BLE_DIAG_RX, BLE_STATUS_RX);
        log("onNotificationReceived");
        log("BLE notification packet");
        logTiming("SUBSCRIBE_TO_NOTIFICATION", _subscribedAtMs, _uptimeMs);
        onNotificationBytes(value);
    }

    function onNotificationBytes(bytes) {
        _lastPayloadLength = byteLength(bytes);

        if ((bytes == null) || (bytes.size() < 6)) {
            handleByteParseError("packet too short");
            return;
        }

        var startIndex = findSimpleBytePayloadStart(bytes);

        if (startIndex < 0) {
            handleByteParseError("S2 marker not found");
            return;
        }

        // Format examples:
        // S2|F|H|58|N|FPV
        // S2|D|M|24|M|MAVIC
        // S2|U|C|X|N|UNKNOWN
        var threatStart = startIndex + 3;
        var threatEnd = findPipeFrom(bytes, threatStart);

        if ((threatEnd - threatStart) != 1) {
            handleByteParseError("bad threat field");
            return;
        }

        var severityStart = threatEnd + 1;
        var severityEnd = findPipeFrom(bytes, severityStart);

        if ((severityEnd - severityStart) != 1) {
            handleByteParseError("bad severity field");
            return;
        }

        var bandStart = severityEnd + 1;
        var bandEnd = findPipeFrom(bytes, bandStart);

        if (bandEnd <= bandStart) {
            handleByteParseError("bad band field");
            return;
        }

        var distanceStart = bandEnd + 1;
        var distanceEnd = findPipeFrom(bytes, distanceStart);

        if ((distanceEnd - distanceStart) != 1) {
            handleByteParseError("bad distance field");
            return;
        }

        var finalFieldStart = distanceEnd + 1;
        var isS2Payload = bytes[startIndex + 1] == 50;
        var threat = threatFromByte(bytes[threatStart]);
        var severity = severityFromByte(bytes[severityStart]);
        var band = bandFromBytes(bytes, bandStart, bandEnd);
        var distance = distanceFromByte(bytes[distanceStart]);
        var confidence = 0;
        var droneClass = "UNKNOWN";

        if (isS2Payload) {
            droneClass = droneClassFromBytes(bytes, finalFieldStart);
        } else {
            confidence = confidenceFromBytes(bytes, finalFieldStart);
        }

        if ((threat == null) || (severity == null) || (band == null) || (distance == null) || (confidence < 0)) {
            handleByteParseError("field mapping failed");
            return;
        }

        _latestAlert = new AlertModel(
            threat,
            severity,
            confidence,
            band,
            distance,
            defaultBandsForBand(band),
            null,
            "BLE_BYTE_PARSE",
            0
        );
        _latestAlert.droneClass = droneClass;

        _hasLatestAlert = true;
        _hasUnreadAlert = true;
        _lastParseOk = true;
        _lastParsedSummary = formatParsedSummary(_latestAlert);
        _lastDirectParseResult = formatParsedSummary(_latestAlert);
        _lastRawPayload = "S1";
        lastRxMs = _uptimeMs;
        explicitDisconnectSeen = false;
        markBridgeActivity("valid s2");
        setLifecycleFlags(false, false, true, true, "byte rx alert");
        setBleState(BLE_STATE_CONNECTED, BLE_DIAG_RX, BLE_STATUS_RX);
        System.println("VALID S2 CLEARS LINK LOST");
        System.println("SKYSHIELD BLE byte parse threat=" + threat + " severity=" + severity + " band=" + band + " distance=" + distance + " droneClass=" + droneClass);

        return;
    }

    function findSimpleBytePayloadStart(bytes) {
        var index = 0;
        var maxIndex = bytes.size() - 2;

        while (index < maxIndex) {
            if ((bytes[index] == 83) && ((bytes[index + 1] == 50) || (bytes[index + 1] == 49)) && (bytes[index + 2] == 124)) {
                return index;
            }

            index += 1;
        }

        return -1;
    }

    function findPipeFrom(bytes, startIndex) {
        var index = startIndex;

        while (index < bytes.size()) {
            if (bytes[index] == 124) {
                return index;
            }

            index += 1;
        }

        return -1;
    }

    function threatFromByte(code) {
        if (code == 70) { return "FPV"; }
        if (code == 68) { return "DJI"; }
        if (code == 85) { return "UNKNOWN"; }
        return null;
    }

    function severityFromByte(code) {
        if (code == 72) { return "HIGH"; }
        if (code == 77) { return "MEDIUM"; }
        if (code == 67) { return "CRITICAL"; }
        if (code == 76) { return "LOW"; }
        return null;
    }

    function bandFromBytes(bytes, startIndex, endIndex) {
        var fieldLength = endIndex - startIndex;

        if ((fieldLength == 1) && (bytes[startIndex] == 88)) {
            return "MULTI";
        }

        if (fieldLength != 2) {
            return null;
        }

        var first = bytes[startIndex];
        var second = bytes[startIndex + 1];

        if ((first == 53) && (second == 56)) { return "5.8GHz"; }
        if ((first == 50) && (second == 52)) { return "2.4GHz"; }
        if ((first == 51) && (second == 51)) { return "3.3GHz"; }
        if ((first == 49) && (second == 50)) { return "1.2GHz"; }

        return null;
    }

    function distanceFromByte(code) {
        if (code == 78) { return "NEAR"; }
        if (code == 77) { return "MID"; }
        if (code == 70) { return "FAR"; }
        return null;
    }

    function confidenceFromBytes(bytes, startIndex) {
        var index = startIndex;
        var confidence = 0;
        var sawDigit = false;

        while (index < bytes.size()) {
            var value = bytes[index];

            if ((value < 48) || (value > 57)) {
                break;
            }

            confidence = (confidence * 10) + (value - 48);
            sawDigit = true;
            index += 1;
        }

        if (!sawDigit) {
            return -1;
        }

        return confidence;
    }

    function droneClassFromBytes(bytes, startIndex) {
        if (matchesBytes(bytes, startIndex, [70, 80, 86])) {
            return "FPV";
        }

        if (matchesBytes(bytes, startIndex, [77, 65, 86, 73, 67])) {
            return "MAVIC";
        }

        if (matchesBytes(bytes, startIndex, [65, 85, 84, 69, 76])) {
            return "AUTEL";
        }

        return "UNKNOWN";
    }

    function matchesBytes(bytes, startIndex, expected) {
        if ((startIndex + expected.size()) > bytes.size()) {
            return false;
        }

        for (var i = 0; i < expected.size(); i += 1) {
            if (bytes[startIndex + i] != expected[i]) {
                return false;
            }
        }

        return true;
    }

    function handleByteParseError(reason) {
        clearLatestAlert();
        _lastParseOk = false;
        _lastDirectParseResult = "ERR PARSE";
        System.println("SKYSHIELD BLE byte parse error=" + reason);
        setBleError(BLE_STAGE_RX, reason);
    }

    function clearLatestAlert() {
        _latestAlert = null;
        _hasLatestAlert = false;
        _hasUnreadAlert = false;
    }

    function defaultBandsForBand(primaryBand) {
        return [
            { :band => "1.2", :level => bandLevel(primaryBand, "1.2GHz") },
            { :band => "2.4", :level => bandLevel(primaryBand, "2.4GHz") },
            { :band => "3.3", :level => bandLevel(primaryBand, "3.3GHz") },
            { :band => "5.8", :level => bandLevel(primaryBand, "5.8GHz") }
        ];
    }

    function bandLevel(primaryBand, candidateBand) {
        if ((primaryBand != null) && primaryBand.equals("MULTI")) {
            return "MED";
        }

        if ((primaryBand != null) && primaryBand.equals(candidateBand)) {
            return "HIGH";
        }

        return "NONE";
    }

    function formatParsedSummary(alert) {
        if (alert == null) {
            return "";
        }

        return alert.threatType + " " + alert.riskLevel + " " + alert.confidencePercent;
    }

    function bytesToUtf8String(bytes) {
        try {
            var decodedString = StringUtil.convertEncodedString(
                bytes,
                {
                    :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                    :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
                    :encoding => StringUtil.CHAR_ENCODING_UTF8
                }
            );

            if (decodedString != null) {
                return decodedString;
            }
        } catch (ex) {
            log("StringUtil UTF-8 conversion failed: " + ex);
        }

        return bytesToAsciiString(bytes);
    }

    function bytesToAsciiString(bytes) {
        if (bytes == null) {
            return null;
        }

        return bytes.toString();
    }

    function byteLength(bytes) {
        if (bytes == null) {
            return 0;
        }

        return bytes.size();
    }

    function setBleState(state, diagState, bleStatus) {
        _state = state;
        setDiagnosticState(diagState, bleStatus);
    }

    function setDiagnosticState(diagState, bleStatus) {
        if ((_diagState == diagState) && (_bleStatus == bleStatus)) {
            return;
        }

        _diagState = diagState;
        _bleStatus = bleStatus;
        updateLastBleStage(diagState);
        _diagElapsedMs = 0;
        _scanTimeoutLogged = false;
        _rxTimeoutLogged = false;
        log("diag " + _diagState);
        log("status " + _bleStatus);
    }

    function setBleError(stage, message) {
        if ((stage == BLE_STAGE_SCAN) || (stage == BLE_STAGE_REG)) {
            setScanError(message);
            return;
        }

        if (isPostSubscribeState() && ((stage != BLE_STAGE_RX) && (stage != BLE_STAGE_PARSE))) {
            System.println("SKYSHIELD BLE: ignored post-subscribe " + stage + " error message=" + message);
            return;
        }

        if (stage == BLE_STAGE_CONN) {
            if (!explicitDisconnectSeen) {
                System.println("SKYSHIELD BLE: ignored false ERR CONN message=" + message);
                return;
            }

            if (isSubscribed || hasEverSubscribed) {
                setDisconnectError(message);
                return;
            }
        }

        _lastBleStage = stage;
        _state = BLE_STATE_SIGNAL_LOST;
        System.println("SKYSHIELD BLE ERROR stage=" + stage + " message=" + message);
        setDiagnosticState(errorLabelForStage(stage), errorLabelForStage(stage));
    }

    function setDisconnectError(message) {
        _lastBleStage = BLE_STAGE_CONN;
        _state = BLE_STATE_SIGNAL_LOST;
        log("explicit disconnect after subscribe");
        System.println("SKYSHIELD BLE ERROR stage=DISC message=" + message);
        setDiagnosticState(BLE_ERR_DISC, BLE_ERR_DISC);
    }

    function setRxTimeoutError(message) {
        _lastBleStage = BLE_STAGE_RX;
        _state = BLE_STATE_SIGNAL_LOST;
        System.println("SKYSHIELD BLE ERROR stage=NOTIFY message=" + message);
        setDiagnosticState(BLE_ERR_RX_TIMEOUT, BLE_ERR_RX_TIMEOUT);
    }

    function isAlertDescriptor(descriptor) {
        if (descriptor == null) {
            return false;
        }

        try {
            var characteristic = descriptor.getCharacteristic();
            return isAlertCharacteristic(characteristic);
        } catch (ex) {
            log("descriptor characteristic check failed: " + ex);
        }

        return false;
    }

    function isAlertCharacteristic(characteristic) {
        if (characteristic == null) {
            return false;
        }

        try {
            var uuid = characteristic.getUuid();

            if (uuid == null) {
                return false;
            }

            return uuid.equals(_alertCharacteristicUuid);
        } catch (ex) {
            log("characteristic UUID check failed: " + ex);
        }

        return false;
    }

    function setScanError(reason) {
        if (!canSetScanError()) {
            System.println("SKYSHIELD BLE: ignored stale ERR SCAN reason=" + reason);
            return;
        }

        _lastBleStage = BLE_STAGE_SCAN;
        _state = BLE_STATE_SIGNAL_LOST;
        System.println("SKYSHIELD BLE ERROR stage=SCAN message=" + reason);
        setDiagnosticState(BLE_ERR_SCAN, BLE_ERR_SCAN);
    }

    function stopScanForConnect() {
        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
            log("scan stop requested for connect");
        } catch (ex) {
            log("scan stop for connect warning: " + ex);
        }
    }

    function setLifecycleFlags(scanning, connecting, connected, subscribed, reason) {
        isScanning = scanning;
        isConnecting = connecting;
        isConnected = connected;
        isSubscribed = subscribed;
        log("flags scan=" + boolText(isScanning) + " connecting=" + boolText(isConnecting) + " connected=" + boolText(isConnected) + " subscribed=" + boolText(isSubscribed) + " reason=" + reason);
    }

    function boolText(value) {
        if (value) {
            return "true";
        }

        return "false";
    }

    function logTiming(label, startMs, endMs) {
        log("timing " + label + " ms=" + (endMs - startMs));
    }

    function logDisconnectTiming() {
        if (hasEverConnected) {
            logTiming("CONNECT_TO_DISCONNECT", _connectStartedAtMs, _disconnectedAtMs);
        }

        if (hasEverSubscribed) {
            logTiming("SUBSCRIBE_TO_DISCONNECT", _subscribedAtMs, _disconnectedAtMs);
        }
    }

    function canProcessScanCallback() {
        if (hasEverFoundPeripheral || hasEverConnected || hasEverSubscribed) {
            return false;
        }

        if (isConnecting || isConnected || isSubscribed) {
            return false;
        }

        if ((_diagState == BLE_DIAG_CONN) ||
            (_diagState == BLE_DIAG_SVC) ||
            (_diagState == BLE_DIAG_CHAR) ||
            (_diagState == BLE_DIAG_SUB) ||
            (_diagState == BLE_DIAG_SUB_WAIT) ||
            (_diagState == BLE_DIAG_RX)) {
            return false;
        }

        return true;
    }

    function isPostSubscribeState() {
        if (isSubscribed) {
            return true;
        }

        if (_diagState == BLE_DIAG_SUB_WAIT) {
            return true;
        }

        if (_diagState == BLE_DIAG_RX) {
            return true;
        }

        return false;
    }

    function canSetScanError() {
        if (hasEverFoundPeripheral || hasEverConnected || hasEverSubscribed) {
            return false;
        }

        if (!canProcessScanCallback()) {
            return false;
        }

        if ((_lastBleStage == BLE_STAGE_SCAN) || (_lastBleStage == BLE_STAGE_REG)) {
            return true;
        }

        if ((_diagState == BLE_DIAG_INIT) ||
            (_diagState == BLE_DIAG_REG) ||
            (_diagState == BLE_DIAG_SCAN)) {
            return true;
        }

        return false;
    }

    function updateLastBleStage(diagState) {
        if (diagState == BLE_DIAG_SCAN) {
            _lastBleStage = BLE_STAGE_SCAN;
            return;
        }

        if (diagState == BLE_DIAG_REG) {
            _lastBleStage = BLE_STAGE_REG;
            return;
        }

        if (diagState == BLE_DIAG_FOUND) {
            _lastBleStage = BLE_STAGE_FOUND;
            return;
        }

        if (diagState == BLE_DIAG_CONN) {
            _lastBleStage = BLE_STAGE_CONN;
            return;
        }

        if (diagState == BLE_DIAG_SVC) {
            _lastBleStage = BLE_STAGE_SVC;
            return;
        }

        if (diagState == BLE_DIAG_CHAR) {
            _lastBleStage = BLE_STAGE_CHAR;
            return;
        }

        if (diagState == BLE_DIAG_SUB) {
            _lastBleStage = BLE_STAGE_SUB;
            return;
        }

        if (diagState == BLE_DIAG_SUB_WAIT) {
            _lastBleStage = BLE_STAGE_SUB;
            return;
        }

        if (diagState == BLE_DIAG_RX) {
            _lastBleStage = BLE_STAGE_RX;
        }
    }

    function errorLabelForStage(stage) {
        if (stage == BLE_STAGE_SCAN) {
            return BLE_ERR_CONN;
        }

        if (stage == BLE_STAGE_REG) {
            return BLE_ERR_CONN;
        }

        if (stage == BLE_STAGE_FOUND) {
            return BLE_ERR_FOUND;
        }

        if (stage == BLE_STAGE_CONN) {
            return BLE_ERR_CONN;
        }

        if (stage == BLE_STAGE_SVC) {
            return BLE_ERR_SVC;
        }

        if (stage == BLE_STAGE_CHAR) {
            return BLE_ERR_CHAR;
        }

        if (stage == BLE_STAGE_SUB) {
            return BLE_ERR_SUB;
        }

        if (stage == BLE_STAGE_RX) {
            return BLE_ERR_RX;
        }

        if (stage == BLE_STAGE_PARSE) {
            return BLE_ERR_PARSE;
        }

        return BLE_ERR_CONN;
    }

    function log(message) {
        System.println("SKYSHIELD BLE: " + message);
    }

    function isFallbackAlert(alert) {
        return (alert.threatType == "UNKNOWN") &&
            (alert.riskLevel == "LOW") &&
            (alert.band == "MULTI") &&
            (alert.distanceLabel == "FAR") &&
            (alert.confidencePercent == 0);
    }

    function getDeviceName() {
        return SKYSHIELD_BLE_DEVICE_NAME;
    }

    function getServiceUuid() {
        return SKYSHIELD_BLE_SERVICE_UUID;
    }

    function getAlertCharacteristicUuid() {
        return SKYSHIELD_BLE_ALERT_CHARACTERISTIC_UUID;
    }

    function isAvailable() {
        return _enabled;
    }
}

class SkyShieldBleDelegate extends Ble.BleDelegate {
    var _source;

    function initialize(source) {
        BleDelegate.initialize();
        _source = source;
    }

    function onProfileRegister(uuid, status) {
        System.println("SKYSHIELD BLE: PROFILE delegate callback entered");
        _source.handleProfileRegister(uuid, status);
    }

    function onScanStateChange(scanState, status) {
        System.println("SKYSHIELD BLE: SCAN delegate callback entered");
        _source.handleScanStateChange(scanState, status);
    }

    function onScanResults(scanResults) {
        System.println("SKYSHIELD BLE: SCAN delegate callback entered");
        _source.handleScanResults(scanResults);
    }

    function onConnectedStateChanged(device, state) {
        System.println("SKYSHIELD BLE: CONNECTED delegate callback entered");
        _source.handleConnectedStateChanged(device, state);
    }

    function onDescriptorWrite(descriptor, status) {
        System.println("SKYSHIELD BLE: SUBSCRIBE delegate callback entered");
        _source.handleDescriptorWrite(descriptor, status);
    }

    function onCharacteristicChanged(characteristic, value) {
        System.println("SKYSHIELD BLE: NOTIFICATION delegate callback entered");
        _source.handleCharacteristicChanged(characteristic, value);
    }
}
