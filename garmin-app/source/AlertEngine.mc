// AlertEngine is intentionally small for the MVP.
// Later, this is where BLE alert ingestion and protocol validation should be added.
class AlertEngine {
    var _provider;

    function initialize() {
        _provider = new MockAlertProvider();
    }

    function getActiveAlert() {
        return _provider.getActiveAlert();
    }

    function isHighUrgency(alert) {
        if (alert == null) {
            return false;
        }

        return (alert.riskLevel == "HIGH") || (alert.riskLevel == "CRITICAL");
    }
}
