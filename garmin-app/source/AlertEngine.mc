import Toybox.System;

// Simulator/dev demo can set USE_MOCK_FALLBACK = true.
const USE_MOCK_FALLBACK = false;
const ALERT_SOURCE_BLE = "BLE";
const ALERT_SOURCE_MOCK = "MOCK";
const ALERT_SOURCE_NONE = "NONE";
const PRIORITY_HOLD_ELEVATED_MS = 8000;
const PRIORITY_HOLD_HIGH_MS = 6000;
const PRIORITY_HOLD_MEDIUM_MS = 4000;
const PRIORITY_HOLD_LOW_MS = 2500;

class AlertEngine {
    var _bleSource;
    var _mockSource;
    var _currentAlert;
    var _currentPriorityAlert;
    var _latestIncomingAlert;
    var _lastIncomingAlertRef;
    var _priorityAcceptedAtMs;
    var _lastIncomingAlertMs;
    var _currentSource;
    var _bleStarted;

    function initialize() {
        _bleSource = new BleAlertSource();
        _mockSource = new MockAlertSource();
        _currentAlert = null;
        _currentPriorityAlert = null;
        _latestIncomingAlert = null;
        _lastIncomingAlertRef = null;
        _priorityAcceptedAtMs = 0;
        _lastIncomingAlertMs = 0;
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
        updatePriorityAlert();

        if (_currentPriorityAlert != null) {
            _currentAlert = _currentPriorityAlert;
            setSource(ALERT_SOURCE_BLE);
            return _currentAlert;
        }

        if ((_bleSource.getBleStatus().equals("RX")) && !_bleSource.wasLastParseOk()) {
            _currentAlert = null;
            setSource(ALERT_SOURCE_NONE);
            return null;
        }

        return _currentAlert;
    }

    function tick(elapsedMs) {
        _bleSource.tick(elapsedMs);
        updatePriorityAlert();

        if (_currentPriorityAlert != null) {
            _currentAlert = _currentPriorityAlert;
            setSource(ALERT_SOURCE_BLE);
            System.println("SKYSHIELD AlertEngine using BLE alert=true");
            return;
        }

        System.println("SKYSHIELD AlertEngine using BLE alert=false");
    }

    function getNextAlert() {
        updatePriorityAlert();

        if (_currentPriorityAlert != null) {
            _currentAlert = _currentPriorityAlert;
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

    function getBleLastRxAgeMs() {
        return _bleSource.getLastRxAgeMs();
    }

    function getBleBridgeActivityAgeMs() {
        return _bleSource.getBridgeActivityAgeMs();
    }

    function isBleLinkAlive() {
        return _bleSource.isLinkAlive();
    }

    function hasBleExplicitDisconnect() {
        return _bleSource.hasExplicitDisconnect();
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

    function hasBleAlert() {
        return _bleSource.hasLatestAlert();
    }

    function getBleAlert() {
        updatePriorityAlert();

        if (_currentPriorityAlert != null) {
            return _currentPriorityAlert;
        }

        return _bleSource.getLatestAlert();
    }

    function getLastIncomingAlertMs() {
        return _lastIncomingAlertMs;
    }

    function updatePriorityAlert() {
        if (!_bleSource.hasLatestAlert()) {
            return;
        }

        var incoming = _bleSource.getLatestAlert();
        var now = System.getTimer();
        var isNewIncoming = incoming != _lastIncomingAlertRef;

        _latestIncomingAlert = incoming;

        if (isNewIncoming) {
            _lastIncomingAlertRef = incoming;
            _lastIncomingAlertMs = now;
        }

        if (_currentPriorityAlert == null) {
            acceptPriorityAlert(incoming, now, "initial");
            return;
        }

        var comparison = compareAlertPriority(incoming, _currentPriorityAlert);

        if (comparison > 0) {
            logPriorityComparison(incoming, _currentPriorityAlert);
            acceptPriorityAlert(incoming, now, "higher");
            System.println("PRIORITY accepted higher");
            return;
        }

        if (comparison == 0) {
            if (shouldAcceptEqualPriorityUpdate(incoming, _currentPriorityAlert)) {
                logPriorityComparison(incoming, _currentPriorityAlert);
                acceptPriorityAlert(incoming, now, "equal update");
                System.println("PRIORITY accepted equal update");
            }

            return;
        }

        if (hasPriorityHoldExpired(_currentPriorityAlert, now)) {
            logPriorityComparison(_latestIncomingAlert, _currentPriorityAlert);
            acceptPriorityAlert(_latestIncomingAlert, now, "aged out");
            System.println("PRIORITY aged out");
            return;
        }

        if (isNewIncoming) {
            logPriorityComparison(incoming, _currentPriorityAlert);
            System.println("PRIORITY suppressed lower");
        }
    }

    function acceptPriorityAlert(alert, now, reason) {
        _currentPriorityAlert = alert;
        _currentAlert = alert;
        _priorityAcceptedAtMs = now;
        setSource(ALERT_SOURCE_BLE);
        System.println("PRIORITY accepted " + reason + " " + formatPriorityAlert(alert));
    }

    function hasPriorityHoldExpired(alert, now) {
        return (now - _priorityAcceptedAtMs) >= getPriorityHoldMs(alert);
    }

    function getPriorityHoldMs(alert) {
        var severity = getSeverityPriority(alert);

        if (severity >= 4) {
            return PRIORITY_HOLD_ELEVATED_MS;
        }

        if (severity == 3) {
            return PRIORITY_HOLD_HIGH_MS;
        }

        if (severity == 2) {
            return PRIORITY_HOLD_MEDIUM_MS;
        }

        return PRIORITY_HOLD_LOW_MS;
    }

    function compareAlertPriority(leftAlert, rightAlert) {
        var leftSeverity = getSeverityPriority(leftAlert);
        var rightSeverity = getSeverityPriority(rightAlert);

        if (leftSeverity != rightSeverity) {
            return leftSeverity - rightSeverity;
        }

        var leftThreat = getThreatPriority(leftAlert);
        var rightThreat = getThreatPriority(rightAlert);

        if (leftThreat != rightThreat) {
            return leftThreat - rightThreat;
        }

        return getBandPriority(leftAlert) - getBandPriority(rightAlert);
    }

    function getSeverityPriority(alert) {
        if ((alert == null) || (alert.riskLevel == null)) {
            return 0;
        }

        if (alert.riskLevel.equals("CRITICAL") || alert.riskLevel.equals("ELEVATED")) {
            return 4;
        }

        if (alert.riskLevel.equals("HIGH")) {
            return 3;
        }

        if (alert.riskLevel.equals("MEDIUM")) {
            return 2;
        }

        if (alert.riskLevel.equals("LOW")) {
            return 1;
        }

        return 0;
    }

    function getThreatPriority(alert) {
        if ((alert == null) || (alert.threatType == null)) {
            return 0;
        }

        if (alert.threatType.equals("FPV")) {
            return 3;
        }

        if (alert.threatType.equals("UNKNOWN")) {
            return 2;
        }

        if (alert.threatType.equals("DJI")) {
            return 1;
        }

        return 0;
    }

    function getBandPriority(alert) {
        if ((alert == null) || (alert.band == null)) {
            return 0;
        }

        if (alert.band.equals("MULTI")) {
            return 3;
        }

        if (alert.band.equals("5.8GHz")) {
            return 2;
        }

        if (alert.band.equals("2.4GHz") || alert.band.equals("1.2GHz") || alert.band.equals("3.3GHz")) {
            return 1;
        }

        return 0;
    }

    function shouldAcceptEqualPriorityUpdate(incoming, current) {
        if ((incoming == null) || (current == null)) {
            return false;
        }

        if (!safeValue(incoming.band).equals(safeValue(current.band))) {
            return true;
        }

        return !safeValue(incoming.droneClass).equals(safeValue(current.droneClass));
    }

    function logPriorityComparison(incoming, current) {
        System.println("PRIORITY current=" + formatPriorityAlert(current));
        System.println("PRIORITY incoming=" + formatPriorityAlert(incoming));
    }

    function formatPriorityAlert(alert) {
        if (alert == null) {
            return "NONE";
        }

        return safeValue(alert.threatType) + "|" +
            safeValue(alert.riskLevel) + "|" +
            safeValue(alert.band) + "|" +
            safeValue(alert.distanceLabel) + "|" +
            safeValue(alert.droneClass);
    }

    function safeValue(value) {
        if (value == null) {
            return "";
        }

        return value;
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

        return ((alert.riskLevel != null) && (alert.riskLevel.equals("HIGH") || alert.riskLevel.equals("CRITICAL")));
    }
}
