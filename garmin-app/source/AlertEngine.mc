// AlertEngine is intentionally small for the MVP.
// Later, this is where BLE alert ingestion and protocol validation should be added.
class AlertEngine {
    var _source;
    var _currentAlert;

    function initialize() {
        _source = new MockAlertSource();
        _currentAlert = _source.getNextAlert();
    }

    function getActiveAlert() {
        return _currentAlert;
    }

    function getNextAlert() {
        _currentAlert = _source.getNextAlert();
        return _currentAlert;
    }

    function isHighUrgency(alert) {
        if (alert == null) {
            return false;
        }

        return (alert.riskLevel == "HIGH") || (alert.riskLevel == "CRITICAL");
    }
}
