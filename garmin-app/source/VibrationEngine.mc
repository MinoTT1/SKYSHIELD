import Toybox.Attention;
import Toybox.System;

// Haptics are only triggered for HIGH and CRITICAL mock alerts in the MVP.
// BLE-driven alerts should reuse this boundary after integration.
class VibrationEngine {
    function initialize() {
    }

    function triggerForAlert(alert) {
        if (alert == null) {
            return;
        }

        if (alert.riskLevel == "HIGH") {
            vibrateHigh();
        } else if (alert.riskLevel == "CRITICAL") {
            vibrateCritical();
        }
    }

    function vibrateHigh() {
        try {
            Attention.vibrate([
                new Attention.VibeProfile(80, 100),
                new Attention.VibeProfile(80, 0),
                new Attention.VibeProfile(80, 100)
            ]);
        } catch (ex) {
            System.println("SKYSHIELD vibration unavailable: " + ex);
        }
    }

    function vibrateCritical() {
        try {
            Attention.vibrate([
                new Attention.VibeProfile(250, 100),
                new Attention.VibeProfile(120, 0),
                new Attention.VibeProfile(250, 100)
            ]);
        } catch (ex) {
            System.println("SKYSHIELD vibration unavailable: " + ex);
        }
    }
}
