using Toybox.BluetoothLowEnergy as Ble;
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

// Reconnect backoff. A drop is normal operation on this product -- range,
// watch sleep and interference all cause them -- so recovery is automatic.
// The delay escalates so a rapidly flapping link cannot spin the radio.
const BLE_RECONNECT_MIN_MS = 1000;
const BLE_RECONNECT_MAX_MS = 8000;

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
    // Dead device awaiting Ble.unpairDevice(). Released from the timer tick, not
    // from inside the BLE callback, so teardown APIs are never called while the
    // stack is mid-disconnect.
    var _res;
    var _devicePendingUnpair;
    var _reconnectPending;
    var _reconnectAtMs;
    var _reconnectDelayMs;
    var _reconnectCount;
    var _stateRecoveryPending;
    var _decoder;
    var _latency;

    function initialize() {
        AlertSource.initialize();
        _decoder = new CborAlertDecoder();
        _latency = new LatencyMonitor();
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
        _res = new BleResourceLog();
        _res.beginSession();
        // Lets onStop() close the session without walking the view hierarchy.
        SkyShieldApp.activeLog = _res;
        _devicePendingUnpair = null;
        _reconnectPending = false;
        _reconnectAtMs = 0;
        _reconnectDelayMs = BLE_RECONNECT_MIN_MS;
        _reconnectCount = 0;
        _stateRecoveryPending = false;
    }

    function start() {
        _enabled = true;
        _res.sourceStarted();
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

            _res.step("setDelegate called");
            Ble.setDelegate(_delegate);
            _res.step("setDelegate returned");
            log("delegate set");
            registerSkyShieldProfile();
            startScan();
        } catch (ex) {
            System.println("SKYSHIELD BLE unavailable.");
            log("scan failed: " + ex);
            setScanError("BLE unavailable: " + ex);
        }
    }

    // Clears everything tied to the dead connection and arms a rescan.
    //
    // The hasEver* latches MUST be reset here. canProcessScanCallback() and
    // canSetScanError() both refuse to act once any of them is true, which is
    // correct while a connection is being established but would permanently
    // ignore scan results after a drop.
    //
    // The delegate and the registered profile are deliberately NOT recreated:
    // they belong to the app, not the connection, and reallocating them on
    // every flap would leak.
    function scheduleReconnect(reason) {
        // Hand the dead device to the unpair queue rather than just dropping the
        // reference. Ble.pairDevice() occupies a slot in the Connect IQ BLE
        // workarea and Ble.unpairDevice() is the only thing that frees it;
        // nulling our own reference releases nothing. Pairing again with the old
        // slot still held is what raised "Error Processing Workarea connections".
        _res.step("teardown 4: scheduleReconnect entered");

        if (_device != null) {
            _devicePendingUnpair = _device;
            _res.step("teardown 5: dead device queued for unpair");
        } else {
            _res.step("teardown 5: NO device reference to queue");
        }

        _device = null;
        _alertCharacteristic = null;
        _stateRecoveryPending = false;

        setLifecycleFlags(false, false, false, false, "reconnect reset");

        hasEverFoundPeripheral = false;
        hasEverConnected = false;
        hasEverSubscribed = false;
        _scanTimeoutLogged = false;
        _rxTimeoutLogged = false;

        if (!_enabled) {
            log("reconnect skipped, source stopped");
            return;
        }

        _reconnectPending = true;
        _reconnectAtMs = _uptimeMs + _reconnectDelayMs;

        log("reconnect armed in " + _reconnectDelayMs + "ms after " + reason);

        // Escalate for the next attempt; reset once a packet actually arrives.
        _reconnectDelayMs = _reconnectDelayMs * 2;

        if (_reconnectDelayMs > BLE_RECONNECT_MAX_MS) {
            _reconnectDelayMs = BLE_RECONNECT_MAX_MS;
        }
    }

    // Frees the Connect IQ BLE workarea slot held by a dead connection.
    //
    // Called from the timer tick, never from inside a BLE callback: invoking
    // teardown APIs while the stack is processing an abrupt disconnect is
    // exactly the condition that faulted.
    //
    // Failure is logged and swallowed. If the peer vanished, the stack may have
    // already released it, and an exception here must not take the app down --
    // the whole point is that a disappearing bridge degrades to LINK LOST.
    function releasePendingDevice() {
        if (_devicePendingUnpair == null) {
            _res.step("releasePendingDevice: nothing queued");
            return;
        }

        var dead = _devicePendingUnpair;
        _devicePendingUnpair = null;

        try {
            _res.unpairAttempt();
            Ble.unpairDevice(dead);
            _res.step("unpairDevice returned");
            log("unpaired dead device, workarea slot released");
        } catch (ex) {
            _res.step("unpairDevice THREW: " + ex);
            log("unpair failed (already released?): " + ex);
        }
    }

    function serviceReconnect() {
        if (!_reconnectPending || !_enabled) {
            return;
        }

        if (_uptimeMs < _reconnectAtMs) {
            return;
        }

        _reconnectPending = false;
        _reconnectCount += 1;

        // MUST happen before the rescan can lead to another pairDevice().
        releasePendingDevice();

        log("reconnect attempt " + _reconnectCount + " starting rescan");

        try {
            _res.scanStopped();
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        } catch (ex) {
            log("reconnect scan reset warning: " + ex);
        }

        startScan();
    }

    function getReconnectCount() {
        return _reconnectCount;
    }

    function stop() {
        _enabled = false;
        _res.sourceStopped();
        _reconnectPending = false;

        if (_device != null) {
            _devicePendingUnpair = _device;
            _device = null;
        }

        _alertCharacteristic = null;
        releasePendingDevice();

        try {
            _res.scanStopped();
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

        serviceReconnect();

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
            _res.profileRegisterAttempt();
            Ble.registerProfile(profile);
            _res.step("registerProfile returned");
            log("profile registration requested");
        } catch (ex) {
            _res.step("registerProfile THREW: " + ex);
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
            _res.scanStarted();
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
            _res.step("setScanState(SCANNING) returned");
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
            _res.scanStopped();
            Ble.setScanState(Ble.SCAN_STATE_OFF);
            log("scan stop requested");
        } catch (ex) {
            log("scan stop warning: " + ex);
        }
    }

    function handleProfileRegister(uuid, status) {
        _res.profileRegisterCallback(status);
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
            _res.pairAttempt();
            _device = Ble.pairDevice(scanResult);
            _res.step("pairDevice returned");

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
            _res.connected();
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

        _res.disconnected(state);
        _res.step("teardown 1: disconnect callback entered");

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

        _res.step("teardown 2: error state set");

        _alertCharacteristic = null;
        _res.step("teardown 3: characteristic reference cleared");

        // Previously this was the end of the line: nothing ever restarted
        // scanning, so a single drop left the watch dark until the app was
        // relaunched. A drop is normal operation, so recovery is automatic.
        scheduleReconnect("disconnect state=" + state);
        _res.step("teardown 6: disconnect callback complete");
    }

    function discoverAlertCharacteristic(device) {
        log("SERVICE callback entered");

        if (device == null) {
            setBleError(BLE_STAGE_SVC, "service discovery skipped, device null");
            return;
        }

        if (explicitDisconnectSeen) {
            log("service discovery skipped, link already gone");
            return;
        }

        // Discovery walks live stack objects. If the peer vanishes mid-discovery
        // -- exactly what a bridge reset does -- these calls can fail rather than
        // return null, so they are wrapped instead of only null-checked.
        var service = null;

        try {
            service = device.getService(_serviceUuid);
        } catch (ex) {
            setBleError(BLE_STAGE_SVC, "service discovery failed: " + ex);
            return;
        }

        if (service == null) {
            setBleError(BLE_STAGE_SVC, "service not discovered");
            return;
        }

        setDiagnosticState(BLE_DIAG_SVC, BLE_STATUS_CONNECT);
        markBridgeActivity("service discovered");
        log("service discovered");
        log("CHAR callback entered");

        try {
            _alertCharacteristic = service.getCharacteristic(_alertCharacteristicUuid);
        } catch (ex) {
            _alertCharacteristic = null;
            setBleError(BLE_STAGE_CHAR, "characteristic discovery failed: " + ex);
            return;
        }

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

        if (explicitDisconnectSeen) {
            log("subscribe skipped, link already gone");
            return;
        }

        var descriptor = null;

        try {
            _res.descriptorLookup();
            descriptor = _alertCharacteristic.getDescriptor(_cccdUuid);
        } catch (ex) {
            setBleError(BLE_STAGE_SUB, "cccd lookup failed: " + ex);
            return;
        }

        if (descriptor == null) {
            setBleError(BLE_STAGE_SUB, "cccd descriptor not discovered");
            return;
        }

        try {
            // Garmin calls onCharacteristicChanged() after notifications are enabled by writing [0x01,0x00] to CCCD 0x2902.
            log("CCCD uuid=0x2902 value=[1,0]");
            _res.subscribeRequested();
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
            _res.subscribeSucceeded();
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
            requestCurrentStateRead();
            return;
        }

        setBleError(BLE_STAGE_SUB, "subscribe status=" + status);
    }

    // Recovers current state after a (re)connect.
    //
    // The bridge keeps the most recent alert readable on the same
    // characteristic, so a READ returns it immediately instead of leaving the
    // operator with a blank HUD until the next alert happens to fire. On a
    // quiet link that could otherwise be minutes.
    function requestCurrentStateRead() {
        // Every one of these must hold. On an abrupt peer disappearance the
        // characteristic reference can outlive the connection behind it, and
        // issuing a read against a dead connection is a BLE-stack fault, not a
        // catchable Monkey C error.
        if ((_alertCharacteristic == null) || (_device == null)) {
            log("state recovery skipped, no live characteristic");
            return;
        }

        if (!isConnected || !isSubscribed || explicitDisconnectSeen) {
            log("state recovery skipped, link not established");
            return;
        }

        try {
            _stateRecoveryPending = true;
            _res.readRequested();
            _alertCharacteristic.requestRead();
            log("state recovery read requested");
        } catch (ex) {
            // Not fatal: notifications still work, the HUD just stays blank
            // until the next alert.
            _stateRecoveryPending = false;
            log("state recovery read unavailable: " + ex);
        }
    }

    function handleCharacteristicRead(characteristic, status, value) {
        _res.readCallback();
        var wasRecovery = _stateRecoveryPending;
        _stateRecoveryPending = false;

        // A read queued before an abrupt drop can complete after teardown has
        // begun. Nothing useful can come of it, and touching the result risks
        // reaching into a freed connection.
        if (explicitDisconnectSeen || !isConnected) {
            log("state recovery result ignored, link already gone");
            return;
        }

        if (!isAlertCharacteristic(characteristic)) {
            return;
        }

        if (status != Ble.STATUS_SUCCESS) {
            log("state recovery read failed status=" + status);
            return;
        }

        if (value == null) {
            log("state recovery read returned no data");
            return;
        }

        if (wasRecovery) {
            log("state recovery read returned " + byteLength(value) + " bytes");
        }

        // Same decode path as a notification. A stale cached alert is still a
        // real alert; freshness is handled by the view's packet-age logic.
        onNotificationBytes(value);
    }

    function handleCharacteristicChanged(characteristic, value) {
        log("NOTIFICATION callback entered");

        // A notification already in flight when the peer vanished must not be
        // processed against a connection that is being torn down.
        if (explicitDisconnectSeen) {
            log("notification ignored, link already gone");
            return;
        }

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

    // Decodes one BLE notification through CborAlertDecoder -- the single
    // decoder on this platform. The previous hand-rolled S2 byte scanner that
    // lived here is gone along with its format.
    function onNotificationBytes(bytes) {
        _lastPayloadLength = byteLength(bytes);

        var result = _decoder.decode(bytes);

        if (!result.isOk()) {
            handleByteParseError(result.status);
            return;
        }

        _latestAlert = result.alert;
        recordLatencySample(_latestAlert);

        // A decoded packet proves the link works, so the next drop starts from
        // the shortest backoff again rather than inheriting an escalated one.
        _reconnectDelayMs = BLE_RECONNECT_MIN_MS;

        _hasLatestAlert = true;
        _hasUnreadAlert = true;
        _lastParseOk = true;
        _lastParsedSummary = formatParsedSummary(_latestAlert);
        _lastDirectParseResult = _lastParsedSummary;
        _lastRawPayload = describePayload(bytes);
        lastRxMs = _uptimeMs;
        explicitDisconnectSeen = false;
        markBridgeActivity("valid alert");
        setLifecycleFlags(false, false, true, true, "rx alert");
        setBleState(BLE_STATE_CONNECTED, BLE_DIAG_RX, BLE_STATUS_RX);
        System.println("VALID ALERT CLEARS LINK LOST");
        System.println("SKYSHIELD BLE decoded kind=" + _latestAlert.alertKind +
            " threat=" + _latestAlert.threatType +
            " severity=" + _latestAlert.riskLevel +
            " band=" + _latestAlert.band +
            " distance=" + _latestAlert.distanceLabel +
            " confidence=" + formatConfidenceForLog(_latestAlert) +
            " droneClass=" + _latestAlert.droneClass +
            " seq=" + _latestAlert.sequence);
    }

    function formatConfidenceForLog(alert) {
        if (!alert.hasConfidence()) {
            return "none";
        }

        return alert.confidencePercent.toString();
    }

    // Short hex preview of what actually arrived, for field debugging. The old
    // code hardcoded this to "S1" regardless of the payload (Finding B-2).
    function describePayload(bytes) {
        if (bytes == null) {
            return "<null>";
        }

        var preview = "";
        var limit = bytes.size();

        if (limit > 12) {
            limit = 12;
        }

        for (var i = 0; i < limit; i += 1) {
            preview += (bytes[i] & 0xFF).format("%02X");
        }

        if (bytes.size() > limit) {
            preview += "..";
        }

        return preview + " (" + bytes.size() + "B)";
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

    // Feeds the packet's CORE timestamp and our local receive time to the
    // latency monitor. See docs/latency-measurement.md for why this is a
    // baseline-relative measurement rather than an absolute one-way figure.
    function recordLatencySample(alert) {
        if (alert == null) {
            return;
        }

        _latency.recordPacket(alert.timestampMs, _uptimeMs, alert.detectorLatencyMs, alert.sequence);
    }

    function getLatencyMonitor() {
        return _latency;
    }

    function formatParsedSummary(alert) {
        if (alert == null) {
            return "";
        }

        var confidence = "--";

        if (alert.hasConfidence()) {
            confidence = alert.confidencePercent.toString();
        }

        return alert.threatType + " " + alert.riskLevel + " " + confidence;
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
        if ((characteristic == null) || (_alertCharacteristicUuid == null)) {
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
            _res.scanStopped();
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

    function onCharacteristicRead(characteristic, status, value) {
        System.println("SKYSHIELD BLE: READ delegate callback entered");
        _source.handleCharacteristicRead(characteristic, status, value);
    }
}
