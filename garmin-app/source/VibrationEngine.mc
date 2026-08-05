import Toybox.Attention;
import Toybox.System;

const HAPTIC_COOLDOWN_MS = 3000;
const HAPTIC_ELEVATED_REPEAT_MS = 10000;

// System-event haptics, distinct from any threat alert.
//
// EVERY threat pattern is a SINGLE pulse that varies only in strength and
// duration (LOW 55/90ms through CRITICAL 100/320ms). System events are
// therefore built as MULTI-PULSE RHYTHMS, so they differ structurally rather
// than merely in intensity. A rhythm is recognisable through a sleeve, in
// motion, under stress; a slightly stronger buzz is not.
//
// LINK LOST is a descending two-part figure: a firm pulse, a clear gap, then a
// weaker but longer pulse. Falling intensity reads as something going away.
// It must never be mistaken for "act now", because it means the opposite:
// nothing is arriving any more.
const HAPTIC_LINK_LOST_PROFILE = [
    [80, 220],
    [0, 160],
    [45, 380]
];

// LINK RESTORED is the mirror image: quieter, ascending, and shorter. Rising
// intensity reads as something returning, and the whole figure is gentler than
// any threat pulse so it cannot be read as an alert.
const HAPTIC_LINK_RESTORED_PROFILE = [
    [35, 120],
    [0, 90],
    [60, 200]
];

const HAPTIC_SYSTEM_NONE = "NONE";
const HAPTIC_SYSTEM_LINK_LOST = "LINK_LOST";
const HAPTIC_SYSTEM_LINK_RESTORED = "LINK_RESTORED";

// Haptics are rate-limited by alert content so screen rotation never causes vibration spam.
class VibrationEngine {
    var _settings;
    var _lastAlertKey;
    var _lastSeverityPriority;
    var _lastVibrationMs;
    var _busyUntilMs;

    // System-event state, deliberately SEPARATE from _lastAlertKey.
    //
    // Routing link events through the alert fingerprint would put them in the
    // same suppression namespace as threats, where a matching key silently
    // cancels the next buzz -- the same class of bug that made AUTEL and
    // UNKNOWN alerts mute each other before AUTEL got its own code. Link
    // events never read or write _lastAlertKey.
    var _lastSystemEvent;

    function initialize(settings) {
        _settings = settings;
        _lastAlertKey = null;
        _lastSeverityPriority = -1;
        _lastVibrationMs = 0;
        _busyUntilMs = 0;
        _lastSystemEvent = HAPTIC_SYSTEM_NONE;
    }

    // Clears THREAT haptic state only. Called when an RF session ends, which
    // says nothing about the BLE link, so _lastSystemEvent is left alone: a
    // link-lost buzz must not be re-armed just because alerts stopped.
    function reset() {
        _lastAlertKey = null;
        _lastSeverityPriority = -1;
        _lastVibrationMs = 0;
        _busyUntilMs = 0;
    }

    // Fires once on entering LINK LOST. Repeated calls while still disconnected
    // are ignored, so the watch does not buzz every render tick or drain the
    // battery while out of range.
    function triggerLinkLost() {
        return playSystemEvent(HAPTIC_SYSTEM_LINK_LOST, HAPTIC_LINK_LOST_PROFILE);
    }

    // Only meaningful after a link loss was actually announced.
    //
    // _operationalState starts at LINK LOST, so the first healthy state after
    // app launch is a LINK-LOST-to-MONITOR transition even though nothing was
    // ever lost. Without this guard the watch would buzz "restored" on every
    // startup. It also keeps the pair symmetric: a loss the operator was never
    // told about produces no recovery buzz either.
    function triggerLinkRestored() {
        if (!_lastSystemEvent.equals(HAPTIC_SYSTEM_LINK_LOST)) {
            System.println("HAPTIC SYSTEM skipped: no announced link loss to restore");
            return false;
        }

        return playSystemEvent(HAPTIC_SYSTEM_LINK_RESTORED, HAPTIC_LINK_RESTORED_PROFILE);
    }

    // Plays a system-event rhythm.
    //
    // Edge-triggered on its own state variable, and deliberately NOT subject to
    // the threat cooldown: a link drop is exactly the moment the operator needs
    // to be told, and suppressing it because a threat buzzed two seconds ago
    // would hide the one event that means "you are no longer covered".
    function playSystemEvent(event, profile) {
        if (_lastSystemEvent.equals(event)) {
            System.println("HAPTIC SYSTEM suppress repeat " + event);
            return false;
        }

        _lastSystemEvent = event;

        if ((_settings != null) && !_settings.vibrationEnabled) {
            System.println("HAPTIC SYSTEM skipped, vibration disabled: " + event);
            return false;
        }

        var profiles = new [profile.size()];
        var totalMs = 0;

        for (var i = 0; i < profile.size(); i += 1) {
            profiles[i] = new Attention.VibeProfile(profile[i][0], profile[i][1]);
            totalMs += profile[i][1];
        }

        try {
            System.println("HAPTIC SYSTEM play " + event + " (" + totalMs + "ms rhythm)");
            Attention.vibrate(profiles);
            _busyUntilMs = System.getTimer() + totalMs;
            return true;
        } catch (ex) {
            System.println("SKYSHIELD system vibration unavailable: " + ex);
        }

        return false;
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

        // Distinct from "U": without this, an AUTEL alert and an UNKNOWN alert
        // would share a fingerprint and suppress each other's haptic.
        if ((value != null) && value.equals("AUTEL")) {
            return "A";
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
