// AlertEngine is intentionally small for the MVP.
// Later, this is where BLE alert ingestion and protocol validation should be added.
class AlertEngine {
    var _bleSource;
    var _mockSource;
    var _currentAlert;

    function initialize() {
        _bleSource = new BleAlertSource();
        _mockSource = new MockAlertSource();
        _bleSource.start();
        _currentAlert = _mockSource.getNextAlert();
    }

    function getActiveAlert() {
        return _currentAlert;
    }

    function getNextAlert() {
        var bleAlert = _bleSource.getNextAlert();

        if (bleAlert != null) {
            _currentAlert = bleAlert;
            return _currentAlert;
        }

        _currentAlert = _mockSource.getNextAlert();
        return _currentAlert;
    }

    function getBleState() {
        return _bleSource.getState();
    }

    function isHighUrgency(alert) {
        if (alert == null) {
            return false;
        }

        return (alert.riskLevel == "HIGH") || (alert.riskLevel == "CRITICAL");
    }
}
