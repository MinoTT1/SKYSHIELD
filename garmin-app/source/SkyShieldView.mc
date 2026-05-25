import Toybox.Graphics;
import Toybox.Timer;
import Toybox.WatchUi;

const SCREEN_ALERT = 0;
const SCREEN_BANDS = 1;
const TIMER_INTERVAL_MS = 250;
const SPLASH_DURATION_MS = 1000;
const ALERT_DURATION_MS = 8000;
const BANDS_DURATION_MS = 1500;
const MOCK_ALERT_ROTATION_MS = 4000;
const CRITICAL_PULSE_MS = 750;
const STALE_PACKET_MS = 10000;
const IDLE_PACKET_MS = 30000;

class SkyShieldView extends WatchUi.View {
    var _engine;
    var _alert;
    var _settings;
    var _history;
    var _connectionState;
    var _actionEngine;
    var _vibrationEngine;
    var _formatter;
    var _timer;
    var _currentScreen;
    var _screenElapsedMs;
    var _alertElapsedMs;
    var _packetAgeMs;
    var _splashElapsedMs;
    var _criticalPulseElapsedMs;
    var _showSplash;
    var _criticalPulseOn;
    var _trackKeys;
    var _trackCounts;
    var _activeTrackStability;

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
        _currentScreen = SCREEN_ALERT;
        _screenElapsedMs = 0;
        _alertElapsedMs = 0;
        _packetAgeMs = 0;
        _splashElapsedMs = 0;
        _criticalPulseElapsedMs = 0;
        _showSplash = true;
        _criticalPulseOn = true;
        resetTrackStability();
    }

    function onShow() {
        _alert = _engine.getActiveAlert();
        resetTrackStability();
        updateTrackStability(_alert);
        _currentScreen = SCREEN_ALERT;
        _screenElapsedMs = 0;
        _alertElapsedMs = 0;
        _packetAgeMs = 0;
        _splashElapsedMs = 0;
        _criticalPulseElapsedMs = 0;
        _showSplash = true;
        _criticalPulseOn = true;
        _connectionState.reset();
        addAlertToHistory(_alert);
        triggerVibrationIfNeeded();

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
                _screenElapsedMs = 0;
                _showSplash = false;
                _currentScreen = SCREEN_ALERT;
                _engine.startBle();
            }

            WatchUi.requestUpdate();
            return;
        }

        _alertElapsedMs += TIMER_INTERVAL_MS;
        updatePacketAge();
        _screenElapsedMs += TIMER_INTERVAL_MS;
        _criticalPulseElapsedMs += TIMER_INTERVAL_MS;
        _engine.tick(TIMER_INTERVAL_MS);

        syncLiveBleAlert();
        updateCriticalPulse();
        updateAlertData();
        updateScreenCycle();

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

    function updateScreenCycle() {
        if (_screenElapsedMs >= getCurrentScreenDurationMs()) {
            advanceScreen();
        }
    }

    function updateAlertData() {
        var activeAlert = _engine.getActiveAlert();

        if (activeAlert != null) {
            if (activeAlert != _alert) {
                _alert = activeAlert;
                _packetAgeMs = 0;
                updateTrackStability(_alert);
                addAlertToHistory(_alert);
                triggerVibrationIfNeeded();
                showAlertForNewAlert();
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
            updateTrackStability(_alert);
            addAlertToHistory(_alert);
            triggerVibrationIfNeeded();
            showAlertForNewAlert();
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

        if (liveAlert == _alert) {
            return;
        }

        _alert = liveAlert;
        _packetAgeMs = 0;
        updateTrackStability(_alert);
        addAlertToHistory(_alert);
        triggerVibrationIfNeeded();
        showAlertForNewAlert();
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

    function advanceScreen() {
        if (_currentScreen == SCREEN_ALERT) {
            setCurrentScreen(SCREEN_BANDS);
            return;
        }

        setCurrentScreen(SCREEN_ALERT);
    }

    function setCurrentScreen(screen) {
        _currentScreen = screen;
        _screenElapsedMs = 0;
    }

    function showAlertForNewAlert() {
        if (_currentScreen == SCREEN_BANDS) {
            setCurrentScreen(SCREEN_ALERT);
        }
    }

    function getCurrentScreenDurationMs() {
        if (_currentScreen == SCREEN_BANDS) {
            return BANDS_DURATION_MS;
        }

        return ALERT_DURATION_MS;
    }

    function triggerVibrationIfNeeded() {
        _vibrationEngine.triggerForAlert(_alert);
    }

    function onUpdate(dc) {
        var width = dc.getWidth();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_showSplash) {
            drawSplashScreen(dc, width);
            return;
        }

        var activeAlert = _engine.getActiveAlert();

        if (activeAlert != null) {
            _alert = activeAlert;
            if (_currentScreen == SCREEN_BANDS) {
                drawBandsScreen(dc, width);
            } else {
                drawAlertScreen(dc, width);
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

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 88, diag, Graphics.FONT_TINY);
        drawCentered(dc, width, 122, "NO DATA", Graphics.FONT_TINY);
        drawBleStatusFooter(dc, width);
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
        if (_alert == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            drawCentered(dc, width, 92, "NO DATA", Graphics.FONT_SMALL);
            drawBleStatusFooter(dc, width);
            return;
        }

        var y = 80;
        var trackState = getSystemHealthState();
        var displaySeverity = _formatter.resolveSeverityForTrack(_alert, trackState);

        drawHealthMetadata(dc, width);
        drawAlertBanner(dc, width, _formatter.formatSeverity(displaySeverity), displaySeverity);
        dc.setColor(getRiskColor(displaySeverity), Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _formatter.formatThreat(_alert.threatType), getAlertTitleFont());
        y += 27;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _formatter.formatConfidence(_alert.confidencePercent), Graphics.FONT_TINY);
        y += 27;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _formatter.formatBand(_alert.band), Graphics.FONT_TINY);
        y += 27;

        drawCentered(dc, width, y, _formatter.formatStrength(_alert.distanceLabel), Graphics.FONT_TINY);

        drawActionState(dc, width, 214);
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
        drawCentered(dc, width, dc.getHeight() - 30, _engine.getBleStatus(), Graphics.FONT_TINY);
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
        if (_alert == null) {
            drawBleStatusFooter(dc, width);
            return;
        }

        var y = 70;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, "BANDS", Graphics.FONT_SMALL);
        y += 34;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);

        for (var i = 0; i < _alert.activeBands.size(); i += 1) {
            var item = _alert.activeBands[i];
            drawCentered(dc, width, y, item[:band] + "  " + item[:level], Graphics.FONT_TINY);
            y += 28;
        }
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

        if ((riskLevel != null) && riskLevel.equals("CRITICAL")) {
            drawCriticalBanner(dc, width, label, margin, top, height);
            return;
        }

        if ((riskLevel != null) && riskLevel.equals("HIGH")) {
            drawHighBanner(dc, width, label, margin, top, height);
            return;
        }

        drawMediumBanner(dc, width, label, margin, top, height);
    }

    function drawMediumBanner(dc, width, label, margin, top, height) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(margin, top + height, width - margin, top + height);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, top + 1, label, Graphics.FONT_SMALL);
    }

    function drawHighBanner(dc, width, label, margin, top, height) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawRectangle(margin, top, width - (margin * 2), height);
        dc.drawRectangle(margin + 1, top + 1, width - (margin * 2) - 2, height - 2);

        drawCentered(dc, width, top + 1, label, Graphics.FONT_SMALL);
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

    function drawActionState(dc, width, y) {
        var action = _actionEngine.getAction(_alert, _connectionState);
        var margin = 46;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(margin, y - 12, width - margin, y - 12);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y + 2, action, Graphics.FONT_TINY);
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
