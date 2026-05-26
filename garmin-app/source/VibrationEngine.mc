import Toybox.Attention;
import Toybox.System;

const HAPTIC_COOLDOWN_MS = 3000;
const HAPTIC_ELEVATED_REPEAT_MS = 10000;

// Haptics are rate-limited by alert content so screen rotation never causes vibration spam.
class VibrationEngine {
    var _settings;
    var _lastAlertKey;
    var _lastSeverityPriority;
    var _lastVibrationMs;
    var _busyUntilMs;

    function initialize(settings) {
        _settings = settings;
        _lastAlertKey = null;
        _lastSeverityPriority = -1;
        _lastVibrationMs = 0;
        _busyUntilMs = 0;
    }

    function reset() {
        _lastAlertKey = null;
        _lastSeverityPriority = -1;
        _lastVibrationMs = 0;
        _busyUntilMs = 0;
    }

    function triggerForAlert(alert) {
        if (alert == null) {
            return;
        }

        if ((_settings != null) && !_settings.vibrationEnabled) {
            return;
        }

        var now = System.getTimer();
        var alertKey = getAlertKey(alert);
        var severity = normalizeSeverity(alert.riskLevel);
        var severityPriority = getSeverityPriority(severity);
        var sameAlert = (_lastAlertKey != null) && _lastAlertKey.equals(alertKey);
        var severityIncreased = severityPriority > _lastSeverityPriority;
        var cooldownElapsed = (now - _lastVibrationMs) >= HAPTIC_COOLDOWN_MS;
        var elevatedRepeatElapsed = (now - _lastVibrationMs) >= HAPTIC_ELEVATED_REPEAT_MS;

        System.println("HAPTIC EVENT fingerprint=" + alertKey + " severity=" + severity);

        if (sameAlert && !isElevated(severity)) {
            System.println("HAPTIC SUPPRESS same fingerprint");
            return;
        }

        if (sameAlert && isElevated(severity) && !elevatedRepeatElapsed) {
            System.println("HAPTIC SUPPRESS same fingerprint");
            return;
        }

        if (!sameAlert && severityIncreased && (_lastAlertKey != null) && !cooldownElapsed) {
            System.println("HAPTIC ALLOW severity escalation");
        } else if ((_lastAlertKey != null) && !cooldownElapsed) {
            System.println("HAPTIC SUPPRESS cooldown");
            return;
        }

        if ((now < _busyUntilMs) && !severityIncreased) {
            System.println("HAPTIC DROP delayed/queued not allowed");
            return;
        }

        if (playImmediatePulse(severity, now)) {
            _lastAlertKey = alertKey;
            _lastSeverityPriority = severityPriority;
            _lastVibrationMs = now;
        }
    }

    function playImmediatePulse(severity, now) {
        var strength = 55;
        var duration = 90;

        if (severity.equals("MEDIUM")) {
            strength = 70;
            duration = 140;
        } else if (severity.equals("HIGH")) {
            strength = 90;
            duration = 190;
        } else if (severity.equals("CRITICAL")) {
            strength = 100;
            duration = 320;
        }

        try {
            System.println("HAPTIC PLAY immediate severity=" + severity);
            Attention.vibrate([
                new Attention.VibeProfile(strength, duration)
            ]);
            _busyUntilMs = now + duration;
            return true;
        } catch (ex) {
            System.println("HAPTIC DROP delayed/queued not allowed");
            System.println("SKYSHIELD vibration unavailable: " + ex);
        }

        return false;
    }

    function getAlertKey(alert) {
        return compactRfType(alert.threatType) + "|" +
            compactSeverity(normalizeSeverity(alert.riskLevel)) + "|" +
            compactBand(alert.band) + "|" +
            compactStrength(alert.distanceLabel) + "|" +
            safeValue(alert.droneClass);
    }

    function compactRfType(value) {
        if ((value != null) && value.equals("FPV")) {
            return "F";
        }

        if ((value != null) && value.equals("DJI")) {
            return "D";
        }

        return "U";
    }

    function compactSeverity(value) {
        if (value.equals("CRITICAL")) {
            return "C";
        }

        if (value.equals("HIGH")) {
            return "H";
        }

        if (value.equals("MEDIUM")) {
            return "M";
        }

        return "L";
    }

    function compactBand(value) {
        if ((value != null) && value.equals("5.8GHz")) {
            return "58";
        }

        if ((value != null) && value.equals("2.4GHz")) {
            return "24";
        }

        if ((value != null) && value.equals("3.3GHz")) {
            return "33";
        }

        if ((value != null) && value.equals("1.2GHz")) {
            return "12";
        }

        return "X";
    }

    function compactStrength(value) {
        if ((value != null) && value.equals("NEAR")) {
            return "N";
        }

        if ((value != null) && value.equals("MID")) {
            return "M";
        }

        return "F";
    }

    function normalizeSeverity(severity) {
        if ((severity != null) && severity.equals("CRITICAL")) {
            return "CRITICAL";
        }

        if ((severity != null) && severity.equals("HIGH")) {
            return "HIGH";
        }

        if ((severity != null) && severity.equals("MEDIUM")) {
            return "MEDIUM";
        }

        return "LOW";
    }

    function getSeverityPriority(severity) {
        if (severity.equals("CRITICAL")) {
            return 3;
        }

        if (severity.equals("HIGH")) {
            return 2;
        }

        if (severity.equals("MEDIUM")) {
            return 1;
        }

        return 0;
    }

    function isElevated(severity) {
        return severity.equals("CRITICAL");
    }

    function safeValue(value) {
        if (value == null) {
            return "";
        }

        return value;
    }
}
