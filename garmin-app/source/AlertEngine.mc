import Toybox.System;

// Simulator/dev demo can set USE_MOCK_FALLBACK = true.
const USE_MOCK_FALLBACK = false;
const ALERT_SOURCE_BLE = "BLE";
const ALERT_SOURCE_MOCK = "MOCK";
const ALERT_SOURCE_NONE = "NONE";

class AlertEngine {
    var _bleSource;
    var _mockSource;
    var _currentAlert;
    var _currentSource;
    var _bleStarted;

    function initialize() {
        _bleSource = new BleAlertSource();
        _mockSource = new MockAlertSource();
        _currentAlert = null;
        _currentSource = ALERT_SOURCE_NONE;
        _bleStarted = false;
        logSource();
    }

    function startBle() {
        if (_bleStarted) {
            return;
        }

        _bleStarted = true;
        _bleSource.start();
    }

    function getActiveAlert() {
        return _currentAlert;
    }

    function tick(elapsedMs) {
        _bleSource.tick(elapsedMs);

        if (_bleSource.hasLatestAlert()) {
            _currentAlert = _bleSource.getLatestAlert();
            setSource(ALERT_SOURCE_BLE);
            System.println("SKYSHIELD AlertEngine using BLE alert=true");
            return;
        }

        System.println("SKYSHIELD AlertEngine using BLE alert=false");
    }

    function getNextAlert() {
        if (_bleSource.hasLatestAlert()) {
            _currentAlert = _bleSource.getLatestAlert();
            setSource(ALERT_SOURCE_BLE);
            System.println("SKYSHIELD AlertEngine using BLE alert=true");
            return _currentAlert;
        }

        var bleAlert = _bleSource.getNextAlert();

        if (bleAlert != null) {
            _currentAlert = bleAlert;
            setSource(ALERT_SOURCE_BLE);
            System.println("SKYSHIELD AlertEngine using BLE alert=true");
            return _currentAlert;
        }

        if (USE_MOCK_FALLBACK) {
            _currentAlert = _mockSource.getNextAlert();
            setSource(ALERT_SOURCE_MOCK);
            System.println("SKYSHIELD AlertEngine using BLE alert=false");
            return _currentAlert;
        }

        _currentAlert = null;
        setSource(ALERT_SOURCE_NONE);
        System.println("SKYSHIELD AlertEngine using BLE alert=false");
        return _currentAlert;
    }

    function getBleState() {
        return _bleSource.getState();
    }

    function getBleDiagnosticState() {
        return _bleSource.getDiagnosticState();
    }

    function getBleStatus() {
        return _bleSource.getBleStatus();
    }

    function getCurrentSource() {
        return _currentSource;
    }

    function getBleLastRawPayload() {
        return _bleSource.getLastRawPayload();
    }

    function wasBleLastParseOk() {
        return _bleSource.wasLastParseOk();
    }

    function getBleLastParsedSummary() {
        return _bleSource.getLastParsedSummary();
    }

    function getBleLastPayloadLength() {
        return _bleSource.getLastPayloadLength();
    }

    function getBleLastDirectParseResult() {
        return _bleSource.getLastDirectParseResult();
    }

    function hasValidBleAlert() {
        return _bleSource.hasValidBleAlert();
    }

    function setSource(source) {
        if (_currentSource == source) {
            return;
        }

        _currentSource = source;
        logSource();
    }

    function logSource() {
        System.println("SKYSHIELD source=" + _currentSource);
        System.println("SKYSHIELD AlertEngine source=" + _currentSource);
    }

    function isHighUrgency(alert) {
        if (alert == null) {
            return false;
        }

        return (alert.riskLevel == "HIGH") || (alert.riskLevel == "CRITICAL");
    }
}
