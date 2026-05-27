import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

const UI_PHASE_ALERT = 0;
const UI_PHASE_BANDS = 1;
const UI_PHASE_IDLE = 2;
const TIMER_INTERVAL_MS = 250;
const SPLASH_DURATION_MS = 1000;
const ALERT_DURATION_MS = 3000;
const BANDS_DURATION_MS = 2000;
const MONITOR_TIMEOUT_MS = 5000;
const UI_CYCLE_MS = 5000;
const MOCK_ALERT_ROTATION_MS = 4000;
const CRITICAL_PULSE_MS = 750;
const STALE_PACKET_MS = 10000;
const IDLE_PACKET_MS = 30000;
const LIVE_ALERT_MS = 5000;
const LINK_LOST_MS = 15000;
const OP_STATE_LIVE = "LIVE";
const OP_STATE_MONITOR = "MONITOR";
const OP_STATE_LINK_LOST = "LINK LOST";

class SkyShieldView extends WatchUi.View {
    var _engine;
    var _alert;
    var _latestAlert;
    var _displayAlert;
    var _settings;
    var _history;
    var _connectionState;
    var _actionEngine;
    var _vibrationEngine;
    var _formatter;
    var _timer;
    var _alertElapsedMs;
    var _packetAgeMs;
    var _splashElapsedMs;
    var _criticalPulseElapsedMs;
    var _showSplash;
    var _criticalPulseOn;
    var _trackKeys;
    var _trackCounts;
    var _activeTrackStability;
    var _uiPhase;
    var _rfSessionActive;
    var _rfSessionStartedMs;
    var _lastValidAlertMs;
    var _lastObservedAlertActivityMs;
    var _uiCycleStartMs;
    var _lastHapticCycleStartMs;
    var _lastHapticSkipCycleStartMs;
    var _lastHapticNonAlertCycleStartMs;
    var _operationalState;

    function initialize() {
        View.initialize();
        _engine = new AlertEngine();
        _settings = new SettingsModel();
        _history = new AlertHistory();
        _connectionState = new ConnectionStateService();
        _actionEngine = new TacticalActionEngine();
        _vibrationEngine = new VibrationEngine(_settings);
        _formatter = new DisplayFormatter();
        _timer = null;
        _latestAlert = null;
        _displayAlert = null;
        _alertElapsedMs = 0;
        _packetAgeMs = 0;
        _splashElapsedMs = 0;
        _criticalPulseElapsedMs = 0;
        _showSplash = true;
        _criticalPulseOn = true;
        _uiPhase = UI_PHASE_IDLE;
        _rfSessionActive = false;
        _rfSessionStartedMs = 0;
        _lastValidAlertMs = 0;
        _lastObservedAlertActivityMs = 0;
        _uiCycleStartMs = 0;
        _lastHapticCycleStartMs = -1;
        _lastHapticSkipCycleStartMs = -1;
        _lastHapticNonAlertCycleStartMs = -1;
        _operationalState = OP_STATE_LINK_LOST;
        resetTrackStability();
    }

    function onShow() {
        _alert = _engine.getActiveAlert();
        _latestAlert = _alert;
        _displayAlert = null;
        resetTrackStability();
        updateTrackStability(_alert);
        _alertElapsedMs = 0;
        _packetAgeMs = 0;
        _splashElapsedMs = 0;
        _criticalPulseElapsedMs = 0;
        _showSplash = true;
        _criticalPulseOn = true;
        _uiPhase = UI_PHASE_IDLE;
        _rfSessionActive = false;
        _rfSessionStartedMs = 0;
        _lastValidAlertMs = 0;
        _lastObservedAlertActivityMs = 0;
        _uiCycleStartMs = 0;
        _lastHapticCycleStartMs = -1;
        _lastHapticSkipCycleStartMs = -1;
        _lastHapticNonAlertCycleStartMs = -1;
        _operationalState = OP_STATE_LINK_LOST;
        _displayAlert = null;
        _connectionState.reset();
        addAlertToHistory(_alert);

        if (_timer == null) {
            _timer = new Timer.Timer();
        }

        _timer.start(method(:onTimerTick), TIMER_INTERVAL_MS, true);
    }

    function onHide() {
        if (_timer != null) {
            _timer.stop();
        }
    }

    function onTimerTick() {
        _connectionState.tick();

        if (_showSplash) {
            _splashElapsedMs += TIMER_INTERVAL_MS;

            if (_splashElapsedMs >= SPLASH_DURATION_MS) {
                _splashElapsedMs = 0;
                _showSplash = false;
                _engine.startBle();
            }

            WatchUi.requestUpdate();
            return;
        }

        _alertElapsedMs += TIMER_INTERVAL_MS;
        updatePacketAge();
        _criticalPulseElapsedMs += TIMER_INTERVAL_MS;
        _engine.tick(TIMER_INTERVAL_MS);

        syncLiveBleAlert();
        updateCriticalPulse();
        updateAlertData();

        WatchUi.requestUpdate();
    }

    function updateCriticalPulse() {
        if ((_alert != null) && (_alert.riskLevel != null) && _alert.riskLevel.equals("CRITICAL")) {
            if (_criticalPulseElapsedMs >= CRITICAL_PULSE_MS) {
                _criticalPulseElapsedMs = 0;
                _criticalPulseOn = !_criticalPulseOn;
            }

            return;
        }

        _criticalPulseElapsedMs = 0;
        _criticalPulseOn = true;
    }

    function hasFreshAlert() {
        return _rfSessionActive;
    }

    function updateAlertData() {
        var activeAlert = _engine.getActiveAlert();

        if (activeAlert != null) {
            noteIncomingAlertActivity();

            if (activeAlert != _alert) {
                var previousAlert = _alert;
                _alert = activeAlert;
                _latestAlert = activeAlert;
                _packetAgeMs = 0;
                updateTrackStability(_alert);
                addAlertToHistory(_alert);
                handleAlertUpdate(previousAlert, _alert);
            }

            return;
        }

        if (!USE_MOCK_FALLBACK) {
            _alert = null;
            return;
        }

        if (_alertElapsedMs >= MOCK_ALERT_ROTATION_MS) {
            _alertElapsedMs = 0;
            _packetAgeMs = 0;
            _alert = _engine.getNextAlert();
            _latestAlert = _alert;
            updateTrackStability(_alert);
            addAlertToHistory(_alert);
            handleAlertUpdate(null, _alert);
        }
    }

    function syncLiveBleAlert() {
        if (_engine.getCurrentSource() != ALERT_SOURCE_BLE) {
            return;
        }

        var liveAlert = _engine.getActiveAlert();

        if (liveAlert == null) {
            return;
        }

        noteIncomingAlertActivity();

        if (liveAlert == _alert) {
            return;
        }

        var previousAlert = _alert;
        _alert = liveAlert;
        _latestAlert = liveAlert;
        _packetAgeMs = 0;
        updateTrackStability(_alert);
        addAlertToHistory(_alert);
        handleAlertUpdate(previousAlert, _alert);
    }

    function handleAlertUpdate(previousAlert, newAlert) {
        if (newAlert == null) {
            return;
        }

        noteValidAlert(System.getTimer());
    }

    function noteIncomingAlertActivity() {
        var activityMs = _engine.getLastIncomingAlertMs();

        if (activityMs <= 0) {
            return;
        }

        if (activityMs <= _lastObservedAlertActivityMs) {
            return;
        }

        _lastObservedAlertActivityMs = activityMs;
        noteValidAlert(activityMs);
    }

    function noteValidAlert(now) {
        _lastValidAlertMs = now;

        if (!_rfSessionActive) {
            _rfSessionActive = true;
            _rfSessionStartedMs = now;
            _uiCycleStartMs = now;
            _displayAlert = _latestAlert;
        }
    }

    function updateRfSessionState(now) {
        if (_rfSessionActive && ((now - _lastValidAlertMs) > MONITOR_TIMEOUT_MS)) {
            _rfSessionActive = false;
            _uiPhase = UI_PHASE_IDLE;
            _displayAlert = null;
            _vibrationEngine.reset();
            _lastHapticCycleStartMs = -1;
            _lastHapticSkipCycleStartMs = -1;
            _lastHapticNonAlertCycleStartMs = -1;
        }
    }

    function updateDisplayCycle(now) {
        if (!_rfSessionActive) {
            return;
        }

        if (_displayAlert == null) {
            _displayAlert = _latestAlert;
            _uiCycleStartMs = now;
            return;
        }

        while ((now - _uiCycleStartMs) >= UI_CYCLE_MS) {
            _uiCycleStartMs += UI_CYCLE_MS;

            if (_latestAlert != null) {
                _displayAlert = _latestAlert;
            }
        }
    }

    function getActiveSessionPhase(now) {
        var elapsed = now - _uiCycleStartMs;

        if (elapsed < 0) {
            elapsed = 0;
        }

        elapsed = elapsed % UI_CYCLE_MS;

        if (elapsed < ALERT_DURATION_MS) {
            return UI_PHASE_ALERT;
        }

        return UI_PHASE_BANDS;
    }

    function addAlertToHistory(alert) {
        if (alert != null) {
            _history.addAlert(alert);
        }
    }

    function resetTrackStability() {
        _trackKeys = ["", "", ""];
        _trackCounts = [0, 0, 0];
        _activeTrackStability = "TRANSIENT";
    }

    function updateTrackStability(alert) {
        if (alert == null) {
            _activeTrackStability = "TRANSIENT";
            return;
        }

        var key = getTrackKey(alert);
        var slot = findTrackSlot(key);

        if (slot < 0) {
            slot = findEmptyTrackSlot();
        }

        if (slot < 0) {
            slot = 0;
        }

        if (_trackKeys[slot] != key) {
            _trackKeys[slot] = key;
            _trackCounts[slot] = 0;
        }

        _trackCounts[slot] += 1;

        if ((_trackCounts[slot] >= 2) && (alert.confidencePercent >= 90)) {
            _activeTrackStability = "LOCKED";
            return;
        }

        if (_trackCounts[slot] >= 2) {
            _activeTrackStability = "STABLE";
            return;
        }

        _activeTrackStability = "TRANSIENT";
    }

    function getTrackKey(alert) {
        return alert.threatType + "|" + alert.band;
    }

    function findTrackSlot(key) {
        for (var i = 0; i < _trackKeys.size(); i += 1) {
            if (_trackKeys[i] == key) {
                return i;
            }
        }

        return -1;
    }

    function findEmptyTrackSlot() {
        for (var i = 0; i < _trackKeys.size(); i += 1) {
            if (_trackKeys[i] == "") {
                return i;
            }
        }

        return -1;
    }

    function updatePacketAge() {
        if (_packetAgeMs < 60000) {
            _packetAgeMs += TIMER_INTERVAL_MS;
        }
    }

    function triggerAlertPhaseHapticIfNeeded(phase) {
        if (phase != UI_PHASE_ALERT) {
            if (_lastHapticNonAlertCycleStartMs != _uiCycleStartMs) {
                _lastHapticNonAlertCycleStartMs = _uiCycleStartMs;
                System.println("HAPTIC SKIP non-alert phase");
            }

            return;
        }

        if (_displayAlert == null) {
            return;
        }

        if (_lastHapticCycleStartMs == _uiCycleStartMs) {
            if (_lastHapticSkipCycleStartMs != _uiCycleStartMs) {
                _lastHapticSkipCycleStartMs = _uiCycleStartMs;
                System.println("HAPTIC SKIP already played for cycle");
            }

            return;
        }

        _lastHapticCycleStartMs = _uiCycleStartMs;
        _lastHapticSkipCycleStartMs = -1;
        System.println("HAPTIC ALERT_PHASE severity=" + _displayAlert.riskLevel);
        _vibrationEngine.triggerForAlert(_displayAlert);
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var now = System.getTimer();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_showSplash) {
            drawSplashScreen(dc, width);
            return;
        }

        var activeAlert = _engine.getActiveAlert();

        if ((activeAlert != null) && (_alert == null)) {
            _alert = activeAlert;
            _latestAlert = activeAlert;
            noteValidAlert(now);
        }

        updateRfSessionState(now);
        updateDisplayCycle(now);

        var operationalState = getOperationalState(now);
        logOperationalState(operationalState);

        if (operationalState.equals(OP_STATE_LINK_LOST)) {
            drawLinkLostScreen(dc, width);
            return;
        }

        if (operationalState.equals(OP_STATE_LIVE) && _rfSessionActive && (_displayAlert != null)) {
            _uiPhase = getActiveSessionPhase(now);
            triggerAlertPhaseHapticIfNeeded(_uiPhase);

            if (_uiPhase == UI_PHASE_ALERT) {
                drawAlertScreen(dc, width);
            } else if (_uiPhase == UI_PHASE_BANDS) {
                drawBandsScreen(dc, width);
            } else {
                drawMonitorScreen(dc, width);
            }

            return;
        }

        var diag = _engine.getBleDiagnosticState();

        if (diag == null) {
            diag = "NO LINK";
        }

        if (diag.equals("RX") && !_engine.wasBleLastParseOk()) {
            drawRxParseError(dc, width);
            return;
        }

        drawMonitorScreen(dc, width);
    }

    function getOperationalState(now) {
        if ((_lastValidAlertMs > 0) && ((now - _lastValidAlertMs) <= LIVE_ALERT_MS)) {
            return OP_STATE_LIVE;
        }

        if (_engine.hasBleExplicitDisconnect()) {
            return OP_STATE_LINK_LOST;
        }

        if (_engine.isBleLinkAlive()) {
            return OP_STATE_MONITOR;
        }

        if (_engine.getBleBridgeActivityAgeMs() > LINK_LOST_MS) {
            return OP_STATE_LINK_LOST;
        }

        return OP_STATE_MONITOR;
    }

    function logOperationalState(state) {
        if ((_operationalState != null) && _operationalState.equals(state)) {
            return;
        }

        _operationalState = state;

        if (state.equals(OP_STATE_LIVE)) {
            System.println("STATE: RECOVERED FROM LINK LOST");
        }

        System.println("STATE: " + state);
    }

    function drawSplashScreen(dc, width) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 96, "SKYSHIELD", Graphics.FONT_SMALL);
        drawCentered(dc, width, 132, "TACTICAL RF DETECTOR", Graphics.FONT_TINY);
    }

    function drawRxNoModelDiagnostic(dc, width) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 66, "RX", Graphics.FONT_TINY);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 96, "LEN " + _engine.getBleLastPayloadLength(), Graphics.FONT_TINY);

        drawCentered(dc, width, 126, "RAW " + truncatePayload(_engine.getBleLastRawPayload()), Graphics.FONT_TINY);

        drawCentered(dc, width, 156, "MAP " + _engine.getBleLastDirectParseResult(), Graphics.FONT_TINY);

        drawBleStatusFooter(dc, width);
    }

    function drawRxParseError(dc, width) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 86, "RX", Graphics.FONT_SMALL);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 120, "RAW " + truncatePayload(_engine.getBleLastRawPayload()), Graphics.FONT_TINY);
        drawCentered(dc, width, 150, "ERR PARSE", Graphics.FONT_TINY);

        drawBleStatusFooter(dc, width);
    }

    function truncatePayload(payload) {
        if (payload == null) {
            return "";
        }

        if (payload.length() <= 18) {
            return payload;
        }

        return payload.substring(0, 18);
    }

    function drawConnectionState(dc, width) {
        var label = getConnectionStateLabel();
        var y = 12;

        if (_connectionState.isSignalLost() && _connectionState.isBlinkOn()) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            drawCentered(dc, width, y, label, Graphics.FONT_TINY);
            return;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, label, Graphics.FONT_TINY);
    }

    function getConnectionStateLabel() {
        if (_connectionState.getState() == "SIGNAL_LOST") {
            return "RF LINK";
        }

        if (_connectionState.getState() == "SCANNING") {
            return "RF ACTIVE";
        }

        if (_connectionState.getState() == "CONNECTING") {
            return "TRACKING";
        }

        if (_connectionState.getState() == "CONNECTED") {
            return "LIVE";
        }

        return "RF ACTIVE";
    }

    function drawAlertScreen(dc, width) {
        var alert = getDisplayAlert();

        if (alert == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            drawCentered(dc, width, 92, "NO DATA", Graphics.FONT_SMALL);
            drawBleStatusFooter(dc, width);
            return;
        }

        var trackState = getSystemHealthState();
        var displaySeverity = _formatter.resolveSeverityForTrack(alert, trackState);
        var severityLabel = _formatter.formatSeverity(displaySeverity);
        var y = 94;

        drawAlertTopSeparator(dc, width);
        drawDroneClassHeader(dc, width, alert);

        dc.setColor(getRiskColor(displaySeverity), Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _formatter.formatThreat(alert.threatType), getAlertTitleFont());
        y += 35;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _formatter.formatBand(alert.band), Graphics.FONT_TINY);
        y += 31;

        drawCentered(dc, width, y, _formatter.formatStrength(alert.distanceLabel), Graphics.FONT_TINY);

        drawActionState(dc, width, 214, alert);
        drawBleStatusFooter(dc, width);
        drawAlertBandActivityMeter(dc, alert);
        drawAlertSeverityMeter(dc, width, severityLabel);
    }

    function drawAlertTopSeparator(dc, width) {
        var margin = 48;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(margin, 76, width - margin, 76);
    }

    function drawDroneClassHeader(dc, width, alert) {
        var label = getDroneClassLabel(alert);
        var font = Graphics.FONT_MEDIUM;
        var y = 35;

        if (label.equals("UNKNOWN")) {
            font = Graphics.FONT_SMALL;
            y = 39;
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, label, font);
        drawCentered(dc, width + 2, y, label, font);
    }

    function getDroneClassLabel(alert) {
        if ((alert == null) || (alert.droneClass == null) || alert.droneClass.equals("")) {
            return "UNKNOWN";
        }

        return alert.droneClass;
    }

    function drawAlertBandActivityMeter(dc, alert) {
        if ((alert == null) || (alert.activeBands == null)) {
            return;
        }

        var labelX = 18;
        var markerX = 43;

        drawAlertBandActivityRow(dc, labelX, markerX, 92, alert, "1.2");
        drawAlertBandActivityRow(dc, labelX, markerX, 114, alert, "2.4");
        drawAlertBandActivityRow(dc, labelX, markerX, 136, alert, "3.3");
        drawAlertBandActivityRow(dc, labelX, markerX, 158, alert, "5.8");
    }

    function drawAlertBandActivityRow(dc, labelX, markerX, y, alert, bandLabel) {
        var level = getActiveBandLevel(alert, bandLabel);

        if (isBandActive(level)) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(labelX, y, Graphics.FONT_XTINY, bandLabel, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(labelX + 1, y, Graphics.FONT_XTINY, bandLabel, Graphics.TEXT_JUSTIFY_LEFT);
            dc.fillRectangle(markerX, y + 8, 3, 3);
            return;
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(labelX, y, Graphics.FONT_XTINY, bandLabel, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function getActiveBandLevel(alert, bandLabel) {
        for (var i = 0; i < alert.activeBands.size(); i += 1) {
            var item = alert.activeBands[i];

            if ((item[:band] != null) && item[:band].equals(bandLabel)) {
                return item[:level];
            }
        }

        return null;
    }

    function isBandActive(level) {
        if (level == null) {
            return false;
        }

        if (level.equals("NONE")) {
            return false;
        }

        if (level.equals("-")) {
            return false;
        }

        if (level.equals("")) {
            return false;
        }

        return level.equals("LOW") ||
            level.equals("MED") ||
            level.equals("MEDIUM") ||
            level.equals("HIGH") ||
            level.equals("ACTIVE");
    }

    function drawAlertSeverityMeter(dc, width, severityLabel) {
        var labelX = width - 46;

        drawSeverityMeterRow(dc, labelX, 92, "LOW", severityLabel);
        drawSeverityMeterRow(dc, labelX, 114, "MED", severityLabel);
        drawSeverityMeterRow(dc, labelX, 136, "HIGH", severityLabel);
        drawSeverityMeterRow(dc, labelX, 158, "ELEV", severityLabel);
    }

    function drawSeverityMeterRow(dc, labelX, y, label, severityLabel) {
        if (isSeverityMeterActive(label, severityLabel)) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(labelX, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(labelX + 1, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(labelX, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function isSeverityMeterActive(label, severityLabel) {
        if (severityLabel == null) {
            return false;
        }

        if (label.equals("LOW") && severityLabel.equals("LOW")) {
            return true;
        }

        if (label.equals("MED") && severityLabel.equals("MEDIUM")) {
            return true;
        }

        if (label.equals("HIGH") && severityLabel.equals("HIGH")) {
            return true;
        }

        if (label.equals("ELEV") && (severityLabel.equals("ELEVATED") || severityLabel.equals("CRITICAL"))) {
            return true;
        }

        return false;
    }

    function getDisplayAlert() {
        if (_displayAlert != null) {
            return _displayAlert;
        }

        return _alert;
    }

    function drawMonitorScreen(dc, width) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 104, "MONITOR", Graphics.FONT_SMALL);

        drawBleStatusFooter(dc, width);
    }

    function drawLinkLostScreen(dc, width) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 104, "LINK LOST", Graphics.FONT_SMALL);
        drawBleStatusFooter(dc, width);
    }

    function drawBleDataProof(dc, width) {
        if (_engine.getCurrentSource() != ALERT_SOURCE_BLE) {
            return;
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 64, "BLE DATA", Graphics.FONT_TINY);
    }

    function drawBleStatusFooter(dc, width) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, dc.getHeight() - 30, getOperatorBleStatusLabel(), Graphics.FONT_TINY);
    }

    function getOperatorBleStatusLabel() {
        if ((_operationalState != null) && _operationalState.equals(OP_STATE_LINK_LOST)) {
            return "LINK LOST";
        }

        return "RX";
    }

    function drawHealthMetadata(dc, width) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 24, getSourceLabel(), Graphics.FONT_TINY);
        drawCentered(dc, width, 38, _formatter.formatTrackState(getSystemHealthState()), Graphics.FONT_TINY);
    }

    function getSourceLabel() {
        var bleDiag = _engine.getBleDiagnosticState();

        if (bleDiag == "RX") {
            return "BLE ACTIVE";
        }

        if (bleDiag == "NOTIFY WAIT") {
            return "BLE WAIT";
        }

        if (bleDiag != null) {
            return bleDiag;
        }

        if (_engine.getCurrentSource() == ALERT_SOURCE_MOCK) {
            return "MOCK";
        }

        return "NO BLE";
    }

    function getPacketAgeLabel() {
        if (_packetAgeMs > STALE_PACKET_MS) {
            return "STALE";
        }

        if (_packetAgeMs >= STALE_PACKET_MS) {
            return "10s";
        }

        if (_packetAgeMs >= 5000) {
            return "5s";
        }

        if (_packetAgeMs >= 2000) {
            return "2s";
        }

        return "NOW";
    }

    function getScanActivityLabel() {
        return _formatter.formatTrackState(getSystemHealthState());
    }

    function getSystemHealthState() {
        if (_alert == null) {
            return "SCAN";
        }

        if (_packetAgeMs > STALE_PACKET_MS) {
            return "STALE";
        }

        if (_activeTrackStability == "LOCKED") {
            return "LOCKED";
        }

        if (_activeTrackStability == "STABLE") {
            return "STABLE";
        }

        return "TRANSIENT";
    }

    function getSystemHealthLabel() {
        return _formatter.formatTrackState(getSystemHealthState());
    }

    function getBleHealthLabel() {
        if (_connectionState.getState() == "SIGNAL_LOST") {
            return "BLE LOST";
        }

        if ((_connectionState.getState() == "SCANNING") || (_connectionState.getState() == "CONNECTING")) {
            return "BLE SCAN";
        }

        return "BLE OK";
    }

    function drawBandsScreen(dc, width) {
        var alert = getDisplayAlert();

        if (alert == null) {
            drawBleStatusFooter(dc, width);
            return;
        }

        var y = 70;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, "BANDS", Graphics.FONT_SMALL);
        y += 34;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);

        for (var i = 0; i < alert.activeBands.size(); i += 1) {
            var item = alert.activeBands[i];
            drawCentered(dc, width, y, item[:band] + "  " + formatBandLevelForBandsScreen(alert, item[:level]), Graphics.FONT_TINY);
            y += 28;
        }
    }

    function formatBandLevelForBandsScreen(alert, level) {
        if ((alert != null) && (alert.band != null) && alert.band.equals("MULTI")) {
            return "ACTIVE";
        }

        return level;
    }

    function drawHistoryScreen(dc, width) {
        var y = 70;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, "HISTORY", Graphics.FONT_SMALL);
        y += 36;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);

        for (var i = 0; (i < _history.size()) && (i < 4); i += 1) {
            var record = _history.getRecordAt(i);

            if (record != null) {
                drawCentered(dc, width, y, formatHistoryRecord(record), Graphics.FONT_TINY);
                y += 28;
            }
        }
    }

    function drawAlertBanner(dc, width, label, riskLevel) {
        var margin = 54;
        var top = 50;
        var height = 19;

        clearAlertBannerArea(dc, width, top, height);

        if ((riskLevel != null) && riskLevel.equals("CRITICAL")) {
            drawCriticalBanner(dc, width, label, margin, top, height);
            return;
        }

        drawMediumBanner(dc, width, label, margin, top, height);
    }

    function clearAlertBannerArea(dc, width, top, height) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, top - 6, width, height + 12);
    }

    function drawMediumBanner(dc, width, label, margin, top, height) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(margin, top + height, width - margin, top + height);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, top + 1, label, Graphics.FONT_SMALL);
    }

    function drawHighBanner(dc, width, label, margin, top, height) {
        drawMediumBanner(dc, width, label, margin, top, height);
    }

    function drawCriticalBanner(dc, width, label, margin, top, height) {
        if (_criticalPulseOn) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
            dc.fillRectangle(margin, top, width - (margin * 2), height);

            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
            drawCentered(dc, width, top + 1, label, Graphics.FONT_SMALL);
            return;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_DK_GRAY);
        dc.fillRectangle(margin, top, width - (margin * 2), height);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_DK_GRAY);
        drawCentered(dc, width, top + 1, label, Graphics.FONT_SMALL);
    }

    function getAlertTitle() {
        return _formatter.formatThreat(_alert.threatType);
    }

    function getAlertTitleFont() {
        return Graphics.FONT_SMALL;
    }

    function getAlertStatus() {
        return _formatter.formatSeverity(_formatter.resolveSeverityForTrack(_alert, getSystemHealthState()));
    }

    function getDistanceLabel() {
        return _formatter.formatStrength(_alert.distanceLabel);
    }

    function getBandLabel() {
        return _formatter.formatBand(_alert.band);
    }

    function drawActionState(dc, width, y, alert) {
        var margin = 46;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(margin, y - 12, width - margin, y - 12);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y + 2, "LIVE", Graphics.FONT_TINY);
    }

    function hasAlertValue(value, expected) {
        if (value == null) {
            return false;
        }

        if (value == expected) {
            return true;
        }

        var index = value.find(expected);
        return (index != null) && (index >= 0);
    }

    function getShortRiskLabel(riskLevel) {
        return _formatter.formatSeverity(riskLevel);
    }

    function formatHistoryRecord(record) {
        return "#" + formatHistorySequence(record[:sequence]) + " " + getHistorySeverity(record[:severity]) + " " + getHistoryThreat(record[:threat]);
    }

    function formatHistorySequence(sequence) {
        var displaySequence = sequence % 100;

        if (displaySequence < 10) {
            return "0" + displaySequence;
        }

        return displaySequence;
    }

    function getHistorySeverity(severity) {
        return _formatter.formatSeverity(severity);
    }

    function getHistoryThreat(threat) {
        if (threat == "UNKNOWN") {
            return "UNK";
        }

        return threat;
    }

    function drawCentered(dc, width, y, text, font) {
        dc.drawText(width / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function getRiskColor(riskLevel) {
        return Graphics.COLOR_WHITE;
    }

}
