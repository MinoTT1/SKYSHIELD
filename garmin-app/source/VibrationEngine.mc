import Toybox.Attention;
import Toybox.System;

// Haptics are triggered from mock alert severity in the MVP.
// BLE-driven alerts should reuse this boundary after integration.
class VibrationEngine {
    var _settings;

    function initialize(settings) {
        _settings = settings;
    }

    function triggerForAlert(alert) {
        if (alert == null) {
            return;
        }

        if ((_settings != null) && !_settings.vibrationEnabled) {
            return;
        }

        if (alert.riskLevel == "MEDIUM") {
            vibrateMedium();
        } else if (alert.riskLevel == "HIGH") {
            vibrateHigh();
        } else if (alert.riskLevel == "CRITICAL") {
            vibrateCritical();
        }
    }

    function vibrateMedium() {
        try {
            Attention.vibrate([
                new Attention.VibeProfile(70, 120)
            ]);
        } catch (ex) {
            System.println("SKYSHIELD vibration unavailable: " + ex);
        }
    }

    function vibrateHigh() {
        try {
            Attention.vibrate([
                new Attention.VibeProfile(85, 100),
                new Attention.VibeProfile(0, 80),
                new Attention.VibeProfile(85, 100),
                new Attention.VibeProfile(0, 80),
                new Attention.VibeProfile(85, 100)
            ]);
        } catch (ex) {
            System.println("SKYSHIELD vibration unavailable: " + ex);
        }
    }

    function vibrateCritical() {
        try {
            Attention.vibrate([
                new Attention.VibeProfile(100, 450),
                new Attention.VibeProfile(0, 160),
                new Attention.VibeProfile(100, 450)
            ]);
        } catch (ex) {
            System.println("SKYSHIELD vibration unavailable: " + ex);
        }
    }
}
