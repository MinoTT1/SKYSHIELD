// Interface-like base class for alert providers.
// Monkey C does not require formal interfaces, so concrete sources just expose getNextAlert().
class AlertSource {
    function initialize() {
    }

    function getNextAlert() {
        return null;
    }
}
