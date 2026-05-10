import Toybox.Graphics;
import Toybox.WatchUi;

class SkyShieldView extends WatchUi.View {
    var _engine;
    var _alert;
    var _vibrationEngine;

    function initialize() {
        View.initialize();
        _engine = new AlertEngine();
        _vibrationEngine = new VibrationEngine();
    }

    function onShow() {
        _alert = _engine.getActiveAlert();

        if (_engine.isHighUrgency(_alert)) {
            _vibrationEngine.triggerForAlert(_alert);
        }
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var y = 10;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_alert == null) {
            drawCentered(dc, width, y, "SKYSHIELD", Graphics.FONT_MEDIUM);
            drawCentered(dc, width, y + 40, "NO ACTIVE ALERT", Graphics.FONT_SMALL);
            return;
        }

        drawCentered(dc, width, y, "SKYSHIELD", Graphics.FONT_MEDIUM);
        y += 34;

        dc.setColor(getRiskColor(_alert.riskLevel), Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _alert.threatType + " " + _alert.riskLevel, Graphics.FONT_LARGE);
        y += 42;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawCentered(dc, width, y, _alert.band + " ACTIVE", Graphics.FONT_MEDIUM);
        y += 34;

        drawLeft(dc, 18, y, "DIST: " + _alert.distanceLabel, Graphics.FONT_MEDIUM);
        y += 30;
        drawLeft(dc, 18, y, "CONF: " + _alert.confidencePercent + "%", Graphics.FONT_MEDIUM);
        y += 40;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawLeft(dc, 18, y, "BANDS:", Graphics.FONT_SMALL);
        y += 26;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawBands(dc, 18, y);
    }

    function drawBands(dc, x, y) {
        for (var i = 0; i < _alert.activeBands.size(); i += 1) {
            var item = _alert.activeBands[i];
            drawLeft(dc, x, y + (i * 24), item[:band] + " " + item[:level], Graphics.FONT_SMALL);
        }
    }

    function drawCentered(dc, width, y, text, font) {
        dc.drawText(width / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawLeft(dc, x, y, text, font) {
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function getRiskColor(riskLevel) {
        if (riskLevel == "CRITICAL") {
            return Graphics.COLOR_RED;
        }

        if (riskLevel == "HIGH") {
            return Graphics.COLOR_ORANGE;
        }

        if (riskLevel == "MED") {
            return Graphics.COLOR_YELLOW;
        }

        return Graphics.COLOR_GREEN;
    }
}
