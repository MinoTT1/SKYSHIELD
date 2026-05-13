// Raw protocol enum values must not be rendered directly on the HUD.
// All user-facing labels must go through DisplayFormatter.
class DisplayFormatter {
    function initialize() {
    }

    function resolveSeverity(alert) {
        return resolveSeverityForTrack(alert, "TRANSIENT");
    }

    function resolveSeverityForTrack(alert, trackState) {
        if (alert == null) {
            return "LOW";
        }

        var severity = alert.riskLevel;

        if (severity == "CRITICAL") {
            return "CRITICAL";
        }

        if (severity == "HIGH") {
            return "HIGH";
        }

        if ((alert.band == "MULTI") && (alert.confidencePercent >= 70)) {
            return "CRITICAL";
        }

        if ((trackState == "LOCKED") && isStrongSignal(alert.distanceLabel)) {
            return "CRITICAL";
        }

        if (trackState == "LOCKED") {
            return "HIGH";
        }

        if ((alert.confidencePercent >= 90) && isStrongSignal(alert.distanceLabel)) {
            if (alert.threatType == "UNKNOWN") {
                return "CRITICAL";
            }

            return "HIGH";
        }

        if ((alert.threatType == "FPV") && (alert.confidencePercent >= 80)) {
            return "HIGH";
        }

        if ((alert.threatType == "DJI") && (alert.confidencePercent >= 70)) {
            return "MEDIUM";
        }

        if (severity == "MEDIUM") {
            return "MEDIUM";
        }

        return "LOW";
    }

    function isStrongSignal(distance) {
        return (distance == "NEAR") || (distance == "STRONG");
    }

    function formatSeverity(severity) {
        if (severity == "CRITICAL") {
            return "ELEVATED";
        }

        if (severity == "HIGH") {
            return "HIGH";
        }

        if (severity == "MEDIUM") {
            return "MEDIUM";
        }

        if (severity == "LOW") {
            return "LOW";
        }

        return "LOW";
    }

    function formatThreat(threat) {
        if (threat == "FPV") {
            return "FPV RF";
        }

        if (threat == "DJI") {
            return "DJI RF";
        }

        if (threat == "UNKNOWN") {
            return "UNKNOWN RF";
        }

        return "UNKNOWN RF";
    }

    function formatBand(band) {
        if (band == "MULTI") {
            return "MULTI RF";
        }

        if (band == "1.2GHz") {
            return "1.2GHz";
        }

        if (band == "2.4GHz") {
            return "2.4GHz";
        }

        if (band == "3.3GHz") {
            return "3.3GHz";
        }

        if (band == "5.8GHz") {
            return "5.8GHz";
        }

        if (band == "1.2 GHz") {
            return "1.2GHz";
        }

        if (band == "2.4 GHz") {
            return "2.4GHz";
        }

        if (band == "3.3 GHz") {
            return "3.3GHz";
        }

        if (band == "5.8 GHz") {
            return "5.8GHz";
        }

        return "MULTI RF";
    }

    function formatStrength(distance) {
        if (distance == "NEAR") {
            return "STRONG";
        }

        if (distance == "MID") {
            return "MODERATE";
        }

        if (distance == "FAR") {
            return "WEAK";
        }

        if (distance == "MED") {
            return "MODERATE";
        }

        if (distance == "STRONG") {
            return "STRONG";
        }

        if (distance == "MODERATE") {
            return "MODERATE";
        }

        if (distance == "WEAK") {
            return "WEAK";
        }

        return "WEAK";
    }

    function formatDirection(direction) {
        if (hasValue(direction, "FRONT")) {
            return "^ FRONT";
        }

        if (hasValue(direction, "LEFT")) {
            return "< LEFT";
        }

        if (hasValue(direction, "RIGHT")) {
            return "> RIGHT";
        }

        if (hasValue(direction, "REAR")) {
            return "v REAR";
        }

        return "";
    }

    function formatTrackState(trackState) {
        if (trackState == "TRANSIENT") {
            return "TRANSIENT";
        }

        if (trackState == "STABLE") {
            return "STABLE";
        }

        if (trackState == "LOCKED") {
            return "LOCKED";
        }

        if (trackState == "STALE") {
            return "STALE";
        }

        return "SCAN";
    }

    function formatConfidence(confidence) {
        return "CONF " + confidence + "%";
    }

    function hasValue(value, expected) {
        if (value == null) {
            return false;
        }

        if (value == expected) {
            return true;
        }

        var index = value.find(expected);
        return (index != null) && (index >= 0);
    }
}
