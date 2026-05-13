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
const BLE_DIAG_INIT = "BLE INIT";
const BLE_DIAG_REG = "BLE REG";
const BLE_DIAG_SCAN = "BLE SCAN";
const BLE_DIAG_FOUND = "BLE FOUND";
const BLE_DIAG_CONN = "BLE CONN";
const BLE_DIAG_SVC = "BLE SVC";
const BLE_DIAG_CHAR = "BLE CHAR";
const BLE_DIAG_SUB = "BLE SUB";
const BLE_DIAG_RX = "BLE RX";
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
const BLE_ERR_RX = "ERR RX";
const BLE_ERR_PARSE = "ERR PARSE";
const BLE_STAGE_TIMEOUT_MS = 20000;

class BleAlertSource extends AlertSource {
    var _parser;
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

    function initialize() {
        AlertSource.initialize();
        _parser = new AlertParser();
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
                setBleError(BLE_STAGE_SCAN, "delegate creation failed");
                return;
            }

            Ble.setDelegate(_delegate);
            log("delegate set");
            registerSkyShieldProfile();
            startScan();
        } catch (ex) {
            System.println("SKYSHIELD BLE unavailable.");
            log("scan failed: " + ex);
            setBleError(BLE_STAGE_SCAN, "BLE unavailable: " + ex);
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
        setBleState(BLE_STATE_DISCONNECTED, BLE_ERR_CONN, BLE_STATUS_OFF);
        log("stopped");
    }

    function tick(elapsedMs) {
        _diagElapsedMs += elapsedMs;

        if ((_diagState == BLE_DIAG_SCAN) && (_diagElapsedMs >= BLE_STAGE_TIMEOUT_MS) && !_scanTimeoutLogged) {
            _scanTimeoutLogged = true;
            log("scan timeout");
        }

        if (((_diagState == BLE_DIAG_CONN) || (_diagState == BLE_DIAG_SVC) || (_diagState == BLE_DIAG_CHAR) || (_diagState == BLE_DIAG_SUB)) &&
            (_diagElapsedMs >= BLE_STAGE_TIMEOUT_MS) && !_rxTimeoutLogged) {
            _rxTimeoutLogged = true;

            if (_diagState == BLE_DIAG_SUB) {
                log("notification timeout after subscribe");
            } else {
                setBleError(_lastBleStage, "BLE pipeline timeout before notifications");
            }
        }
    }

    function getNextAlert() {
        if (!_enabled) {
            return null;
        }

        if (!_hasUnreadAlert) {
            return null;
        }

        _hasUnreadAlert = false;
        return _latestAlert;
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

    function hasConnection() {
        return _state == BLE_STATE_CONNECTED;
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

        setLifecycleFlags(true, false, false, false, "scan start");
        setBleState(BLE_STATE_SCANNING, BLE_DIAG_SCAN, BLE_STATUS_SCAN);
        log("scan requested");

        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        } catch (ex) {
            setLifecycleFlags(false, false, false, false, "scan start failed");
            log("scan failed: " + ex);
            setBleError(BLE_STAGE_SCAN, "scan failed: " + ex);
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
        log("profile registered status=" + status);

        if (status == Ble.STATUS_SUCCESS) {
            _profileRegistered = true;
            log("profile registered");
            return;
        }

        log("profile registration failed status=" + status);
    }

    function handleScanStateChange(scanState, status) {
        log("scan state=" + scanState + " status=" + status);

        if (status != Ble.STATUS_SUCCESS) {
            log("scan failed: status=" + status);

            if (isConnecting || isConnected) {
                log("scan failure ignored after connect started");
                return;
            }

            if (isScanning) {
                setLifecycleFlags(false, false, false, false, "scan failed callback");
                setBleError(BLE_STAGE_SCAN, "scan failed status=" + status);
            }

            return;
        }

        if (scanState == Ble.SCAN_STATE_SCANNING) {
            setLifecycleFlags(true, false, false, false, "scan started");
            log("scan started");
        }
    }

    function handleScanResults(scanResults) {
        var result = scanResults.next();

        while (result != null) {
            logScanResult(result);

            if (isSkyShieldPeripheral(result)) {
                log("BLE matched SKYSHIELD peripheral");
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
            setLifecycleFlags(false, false, true, false, "connected");
            setBleState(BLE_STATE_CONNECTED, BLE_DIAG_CONN, BLE_STATUS_CONNECT);
            log("BLE connected");
            discoverAlertCharacteristic(device);
            return;
        }

        setLifecycleFlags(false, false, false, false, "disconnect");
        setBleError(_lastBleStage, "disconnected state=" + state);
        _alertCharacteristic = null;
    }

    function discoverAlertCharacteristic(device) {
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
        log("service discovered");

        _alertCharacteristic = service.getCharacteristic(_alertCharacteristicUuid);

        if (_alertCharacteristic == null) {
            setBleError(BLE_STAGE_CHAR, "characteristic not discovered");
            return;
        }

        setDiagnosticState(BLE_DIAG_CHAR, BLE_STATUS_CONNECT);
        log("characteristic discovered");
        subscribeToAlertCharacteristic();
    }

    function subscribeToAlertCharacteristic() {
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
            descriptor.requestWrite([1, 0]b);
            setDiagnosticState(BLE_DIAG_SUB, BLE_STATUS_SUBSCRIBE);
            log("subscribe requested");
        } catch (ex) {
            setBleError(BLE_STAGE_SUB, "subscribe failed: " + ex);
        }
    }

    function handleDescriptorWrite(descriptor, status) {
        if (status == Ble.STATUS_SUCCESS) {
            setLifecycleFlags(false, false, true, true, "subscribed");
            setDiagnosticState(BLE_DIAG_SUB, BLE_STATUS_SUBSCRIBE);
            log("BLE subscribed");
            return;
        }

        setBleError(BLE_STAGE_SUB, "subscribe status=" + status);
    }

    function handleCharacteristicChanged(characteristic, value) {
        setLifecycleFlags(false, false, true, true, "rx packet");
        setDiagnosticState(BLE_DIAG_RX, BLE_STATUS_RX);
        log("BLE RX packet");
        onNotificationBytes(value);
    }

    function onNotificationBytes(bytes) {
        System.println("SKYSHIELD BLE raw bytes length: " + byteLength(bytes));

        var jsonString = bytesToUtf8String(bytes);

        if (jsonString == null) {
            setBleError(BLE_STAGE_RX, "packet decode failed");
            return;
        }

        var cleanJsonString = cleanJsonPayload(jsonString);

        if ((cleanJsonString == null) || (cleanJsonString.length() == 0)) {
            setBleError(BLE_STAGE_RX, "packet cleanup failed");
            return;
        }

        System.println("SKYSHIELD BLE raw payload: " + cleanJsonString);
        onNotificationString(cleanJsonString);
    }

    function onNotificationString(jsonString) {
        log("packet received: " + jsonString);

        var parsedAlert = _parser.parse(jsonString);

        if (parsedAlert == null) {
            setBleError(BLE_STAGE_PARSE, "parser failure");
            return;
        }

        if (isFallbackAlert(parsedAlert)) {
            System.println("SKYSHIELD BLE parse fallback");
            setBleError(BLE_STAGE_PARSE, "parser failure: fallback alert returned");
            return;
        }

        _latestAlert = parsedAlert;
        _hasUnreadAlert = true;
        setBleState(BLE_STATE_CONNECTED, BLE_DIAG_RX, BLE_STATUS_RX);
        log("parser success");
    }

    function bytesToUtf8String(bytes) {
        try {
            return StringUtil.convertEncodedString(
                bytes,
                {
                    :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                    :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
                    :encoding => StringUtil.CHAR_ENCODING_UTF8
                }
            );
        } catch (ex) {
            setBleError(BLE_STAGE_RX, "UTF-8 conversion failed: " + ex);
        }

        return null;
    }

    function cleanJsonPayload(decodedString) {
        var startIndex = decodedString.find("{");

        if ((startIndex == null) || (startIndex < 0)) {
            return "";
        }

        var endIndex = findLastIndex(decodedString, "}");

        if ((endIndex == null) || (endIndex < startIndex)) {
            return "";
        }

        return decodedString.substring(startIndex, endIndex + 1);
    }

    function findLastIndex(text, token) {
        var index = 0;
        var lastIndex = null;
        var textLength = text.length();

        while (index < textLength) {
            if (text.substring(index, index + 1) == token) {
                lastIndex = index;
            }

            index += 1;
        }

        return lastIndex;
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
        _lastBleStage = stage;
        _state = BLE_STATE_SIGNAL_LOST;
        System.println("SKYSHIELD BLE ERROR stage=" + stage + " message=" + message);
        setDiagnosticState(errorLabelForStage(stage), errorLabelForStage(stage));
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

        if (diagState == BLE_DIAG_RX) {
            _lastBleStage = BLE_STAGE_RX;
        }
    }

    function errorLabelForStage(stage) {
        if (stage == BLE_STAGE_SCAN) {
            return BLE_ERR_SCAN;
        }

        if (stage == BLE_STAGE_REG) {
            return BLE_ERR_SCAN;
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

        return BLE_ERR_SCAN;
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
        _source.handleProfileRegister(uuid, status);
    }

    function onScanStateChange(scanState, status) {
        _source.handleScanStateChange(scanState, status);
    }

    function onScanResults(scanResults) {
        _source.handleScanResults(scanResults);
    }

    function onConnectedStateChanged(device, state) {
        _source.handleConnectedStateChanged(device, state);
    }

    function onDescriptorWrite(descriptor, status) {
        _source.handleDescriptorWrite(descriptor, status);
    }

    function onCharacteristicChanged(characteristic, value) {
        _source.handleCharacteristicChanged(characteristic, value);
    }
}
