import Toybox.Graphics;
import Toybox.Timer;
import Toybox.WatchUi;

class SkyShieldView extends WatchUi.View {
    var _engine;
    var _alert;
    var _settings;
    var _history;
    var _vibrationEngine;
    var _timer;
    var _screenPhase;
    var _tickCount;
    var _screenTickCount;
    var _showSplash;
    var _criticalPulseOn;

    function initialize() {
        View.initialize();
        _engine = new AlertEngine();
        _settings = new SettingsModel();
        _history = new AlertHistory();
        _vibrationEngine = new VibrationEngine(_settings);
        _timer = null;
        _screenPhase = 0;
        _tickCount = 0;
        _screenTickCount = 0;
        _showSplash = true;
        _criticalPulseOn = true;
    }

    function onShow() {
        _alert = _engine.getActiveAlert();
        _screenPhase = 0;
        _tickCount = 0;
        _screenTickCount = 0;
        _showSplash = true;
        _criticalPulseOn = true;
        _history.addAlert(_alert);
        triggerVibrationIfNeeded();

        if (_timer == null) {
            _timer = new Timer.Timer();
        }

        _timer.start(method(:onTimerTick), 250, true);
    }

    function onHide() {
        if (_timer != null) {
            _timer.stop();
        }
    }

    function onTimerTick() {
        if (_showSplash) {
            _tickCount += 1;

            if (_tickCount >= 4) {
                _tickCount = 0;
                _screenTickCount = 0;
                _showSplash = false;
            }

            WatchUi.requestUpdate();
            return;
        }

        _tickCount += 1;
        _screenTickCount += 1;

        if ((_alert != null) && (_alert.riskLevel == "CRITICAL") && ((_tickCount % 3) == 0)) {
            _criticalPulseOn = !_criticalPulseOn;
        } else if ((_alert == null) || (_alert.riskLevel != "CRITICAL")) {
            _criticalPulseOn = true;
        }

        if (_screenTickCount >= 24) {
            _screenTickCount = 0;
        }

        if (_screenTickCount >= 18) {
            _screenPhase = 2;
        } else if (_screenTickCount >= 12) {
            _screenPhase = 1;
        } else {
            _screenPhase = 0;
        }

        if (_tickCount >= 16) {
            _tickCount = 0;
            _criticalPulseOn = true;
            _alert = _engine.getNextAlert();
            _history.addAlert(_alert);
            triggerVibrationIfNeeded();
        }

        WatchUi.requestUpdate();
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

        if (_alert == null) {
            drawAlertBanner(dc, width, "LOW", "LOW");
            drawCentered(dc, width, 86, "SKYSHIELD", Graphics.FONT_SMALL);
            drawCentered(dc, width, 124, "NO ACTIVE ALERT", Graphics.FONT_TINY);
            return;
        }

        if (_screenPhase == 1) {
            drawBandsScreen(dc, width);
        } else if (_screenPhase == 2) {
            drawHistoryScreen(dc, width);
        } else {
            drawAlertScreen(dc, width);
        }
    }

    function drawSplashScreen(dc, width) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, 96, "SKYSHIELD", Graphics.FONT_SMALL);
        drawCentered(dc, width, 132, "TACTICAL RF DETECTOR", Graphics.FONT_TINY);
    }

    function drawAlertScreen(dc, width) {
        var y = 64;

        drawAlertBanner(dc, width, getShortRiskLabel(_alert.riskLevel), _alert.riskLevel);
        dc.setColor(getRiskColor(_alert.riskLevel), Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, getAlertTitle(), getAlertTitleFont());
        y += 40;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _alert.band, Graphics.FONT_SMALL);
        y += 36;

        drawCentered(dc, width, y, getDistanceLabel(), Graphics.FONT_SMALL);
        y += 36;

        drawCentered(dc, width, y, "CONF " + _alert.confidencePercent + "%", Graphics.FONT_SMALL);
    }

    function drawBandsScreen(dc, width) {
        var y = 58;

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
        var y = 58;

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
        var top = 30;
        var height = 19;

        if (riskLevel == "CRITICAL") {
            drawCriticalBanner(dc, width, label, margin, top, height);
            return;
        }

        if (riskLevel == "HIGH") {
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
        return _alert.threatType + " " + getAlertStatus();
    }

    function getAlertTitleFont() {
        return Graphics.FONT_SMALL;
    }

    function getAlertStatus() {
        if (_alert.riskLevel == "CRITICAL") {
            return "CRITICAL";
        }

        if (_alert.threatType == "FPV") {
            return "ATTACK";
        }

        return "SIGNAL";
    }

    function getDistanceLabel() {
        if (_alert.distanceLabel == "MED") {
            return "MID";
        }

        return _alert.distanceLabel;
    }

    function getShortRiskLabel(riskLevel) {
        if (riskLevel == "CRITICAL") {
            return "!!! CRITICAL !!!";
        }

        if (riskLevel == "MEDIUM") {
            return "MED";
        }

        return riskLevel;
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
        if (severity == "CRITICAL") {
            return "CRIT";
        }

        if (severity == "MEDIUM") {
            return "MED";
        }

        return "HIGH";
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
        if (riskLevel == "CRITICAL") {
            return Graphics.COLOR_RED;
        }

        if (riskLevel == "HIGH") {
            return Graphics.COLOR_GREEN;
        }

        if (riskLevel == "MEDIUM") {
            return Graphics.COLOR_YELLOW;
        }

        return Graphics.COLOR_WHITE;
    }

}
