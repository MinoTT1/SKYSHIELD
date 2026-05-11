// Centralized tactical action mapping for the Garmin HUD.
// The view renders this output, but does not own the decision rules.
class TacticalActionEngine {
    function initialize() {
    }

    function getAction(alert, connectionState) {
        if ((connectionState != null) && connectionState.isSignalLost()) {
            return "NO RF LINK";
        }

        if (alert == null) {
            return "MONITOR";
        }

        return "MONITOR";
    }
}
