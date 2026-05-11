// Centralized tactical action mapping for the Garmin HUD.
// The view renders this output, but does not own the decision rules.
class TacticalActionEngine {
    function initialize() {
    }

    function getAction(alert, connectionState) {
        if ((connectionState != null) && connectionState.isSignalLost()) {
            return "SIGNAL LOST";
        }

        if (alert == null) {
            return "MONITOR";
        }

        var risk = normalizeRisk(alert.riskLevel);
        var distance = normalizeDistance(alert.distanceLabel);

        if ((risk == "CRITICAL") && (distance == "NEAR")) {
            return "TAKE COVER";
        }

        if ((risk == "HIGH") && (distance == "NEAR")) {
            return "TAKE COVER";
        }

        if (risk == "CRITICAL") {
            return "ALERT";
        }

        if (risk == "HIGH") {
            return "ALERT";
        }

        if ((risk == "MEDIUM") || (risk == "LOW")) {
            return "MONITOR";
        }

        return "MONITOR";
    }

    function normalizeDistance(distance) {
        if (matchesValue(distance, "NEAR")) {
            return "NEAR";
        }

        if (matchesValue(distance, "MID")) {
            return "MID";
        }

        if (matchesValue(distance, "FAR")) {
            return "FAR";
        }

        if (distance == "MED") {
            return "MID";
        }

        return distance;
    }

    function normalizeRisk(risk) {
        if (matchesValue(risk, "CRITICAL")) {
            return "CRITICAL";
        }

        if (matchesValue(risk, "HIGH")) {
            return "HIGH";
        }

        if (matchesValue(risk, "MEDIUM")) {
            return "MEDIUM";
        }

        if (matchesValue(risk, "LOW")) {
            return "LOW";
        }

        return risk;
    }

    function matchesValue(value, expected) {
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
