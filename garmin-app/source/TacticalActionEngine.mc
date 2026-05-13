// Centralized tactical action mapping for the Garmin HUD.
// The view renders this output, but does not own the decision rules.
class TacticalActionEngine {
    function initialize() {
    }

    function getAction(alert, connectionState) {
        if (alert == null) {
            return "MONITOR";
        }

        // Until classification is validated, the HUD should recommend monitoring
        // instead of implying a confirmed physical threat or command action.
        return "MONITOR";
    }
}
