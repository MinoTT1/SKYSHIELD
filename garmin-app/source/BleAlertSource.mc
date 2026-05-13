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
    }

    function start() {
        _enabled = true;

        try {
            _serviceUuid = Ble.stringToUuid(SKYSHIELD_BLE_SERVICE_UUID);
            _alertCharacteristicUuid = Ble.stringToUuid(SKYSHIELD_BLE_ALERT_CHARACTERISTIC_UUID);
            _cccdUuid = Ble.cccdUuid();

            _delegate = new SkyShieldBleDelegate(self);
            Ble.setDelegate(_delegate);
            registerSkyShieldProfile();
            startScan();
        } catch (ex) {
            setState(BLE_STATE_SIGNAL_LOST);
            log("BLE unavailable, using mock fallback: " + ex);
        }
    }

    function stop() {
        _enabled = false;

        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        } catch (ex) {
            log("stop warning: " + ex);
        }

        setState(BLE_STATE_DISCONNECTED);
        log("stopped");
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

    function isConnected() {
        return _state == BLE_STATE_CONNECTED;
    }

    function registerSkyShieldProfile() {
        var profile = {
            :uuid => _serviceUuid,
            :characteristics => [
                {
                    :uuid => _alertCharacteristicUuid,
                    :descriptors => [ _cccdUuid ]
                }
            ]
        };

        Ble.registerProfile(profile);
        log("profile registration requested");
    }

    function startScan() {
        if (!_enabled) {
            return;
        }

        setState(BLE_STATE_SCANNING);
        log("scan start");
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
    }

    function stopScan() {
        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        } catch (ex) {
            log("scan stop warning: " + ex);
        }
    }

    function handleProfileRegister(uuid, status) {
        log("profile registered status=" + status);
    }

    function handleScanStateChange(scanState, status) {
        log("scan state=" + scanState + " status=" + status);
    }

    function handleScanResults(scanResults) {
        var result = scanResults.next();

        while (result != null) {
            var deviceName = result.getDeviceName();

            if (deviceName != null) {
                log("peripheral found: " + deviceName);

                if (deviceName == SKYSHIELD_BLE_DEVICE_NAME) {
                    connectToScanResult(result);
                    return;
                }
            }

            result = scanResults.next();
        }
    }

    function connectToScanResult(scanResult) {
        setState(BLE_STATE_CONNECTING);
        log("connecting");
        stopScan();

        try {
            _device = Ble.pairDevice(scanResult);

            if (_device == null) {
                log("pairDevice returned null");
                setState(BLE_STATE_SIGNAL_LOST);
                startScan();
            }
        } catch (ex) {
            log("connect failed: " + ex);
            setState(BLE_STATE_SIGNAL_LOST);
            startScan();
        }
    }

    function handleConnectedStateChanged(device, state) {
        _device = device;

        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            setState(BLE_STATE_CONNECTED);
            log("connected");
            discoverAlertCharacteristic(device);
            return;
        }

        setState(BLE_STATE_SIGNAL_LOST);
        log("disconnected state=" + state);
        _alertCharacteristic = null;

        if (_enabled) {
            startScan();
        }
    }

    function discoverAlertCharacteristic(device) {
        if (device == null) {
            log("service discovery skipped, device null");
            return;
        }

        var service = device.getService(_serviceUuid);

        if (service == null) {
            log("service not discovered");
            return;
        }

        log("service discovered");

        _alertCharacteristic = service.getCharacteristic(_alertCharacteristicUuid);

        if (_alertCharacteristic == null) {
            log("characteristic not discovered");
            return;
        }

        log("characteristic discovered");
        subscribeToAlertCharacteristic();
    }

    function subscribeToAlertCharacteristic() {
        if (_alertCharacteristic == null) {
            log("subscribe skipped, characteristic null");
            return;
        }

        var descriptor = _alertCharacteristic.getDescriptor(_cccdUuid);

        if (descriptor == null) {
            log("cccd descriptor not discovered");
            return;
        }

        try {
            descriptor.requestWrite([1, 0]b);
            log("subscribe requested");
        } catch (ex) {
            log("subscribe failed: " + ex);
        }
    }

    function handleDescriptorWrite(descriptor, status) {
        if (status == Ble.STATUS_SUCCESS) {
            log("subscribed");
            return;
        }

        log("subscribe status=" + status);
    }

    function handleCharacteristicChanged(characteristic, value) {
        log("notification received");
        onNotificationBytes(value);
    }

    function onNotificationBytes(bytes) {
        var jsonString = bytesToUtf8String(bytes);

        if (jsonString == null) {
            log("packet decode failed");
            return;
        }

        onNotificationString(jsonString);
    }

    function onNotificationString(jsonString) {
        log("packet received: " + jsonString);

        var parsedAlert = _parser.parse(jsonString);

        if (parsedAlert == null) {
            log("parser failure");
            return;
        }

        if (isFallbackAlert(parsedAlert)) {
            log("parser failure: fallback alert returned");
            return;
        }

        _latestAlert = parsedAlert;
        _hasUnreadAlert = true;
        setState(BLE_STATE_CONNECTED);
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
            log("UTF-8 conversion failed: " + ex);
        }

        return null;
    }

    function setState(state) {
        _state = state;
    }

    function log(message) {
        System.println("SKYSHIELD BLE: " + message);
    }

    function isFallbackAlert(alert) {
        return (alert.source == "") && (alert.sequence == 0) && (alert.confidencePercent == 0);
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
