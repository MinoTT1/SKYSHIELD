// Hardcoded MVP data. No RF detection and no BLE are used in this prototype.
class MockAlertProvider {
    var _alertIndex;
    var _parser;
    var _mockAlerts;

    function initialize() {
        _alertIndex = 0;
        _parser = new AlertParser();
        _mockAlerts = [
            "{\"threat\":\"FPV\",\"severity\":\"HIGH\",\"band\":\"5.8GHz\",\"distance\":\"NEAR\",\"confidence\":87,\"bands\":{\"band_1_2\":\"LOW\",\"band_2_4\":\"LOW\",\"band_3_3\":\"MED\",\"band_5_8\":\"HIGH\"},\"source\":\"GARMIN_MOCK\",\"sequence\":1}",
            "{\"threat\":\"DJI\",\"severity\":\"MEDIUM\",\"band\":\"2.4GHz\",\"distance\":\"MID\",\"confidence\":72,\"bands\":{\"band_1_2\":\"LOW\",\"band_2_4\":\"MED\",\"band_3_3\":\"MED\",\"band_5_8\":\"LOW\"},\"source\":\"GARMIN_MOCK\",\"sequence\":2}",
            "{\"threat\":\"UNKNOWN\",\"severity\":\"CRITICAL\",\"band\":\"MULTI\",\"distance\":\"NEAR\",\"confidence\":94,\"bands\":{\"band_1_2\":\"HIGH\",\"band_2_4\":\"MED\",\"band_3_3\":\"MED\",\"band_5_8\":\"HIGH\"},\"source\":\"GARMIN_MOCK\",\"sequence\":3}"
        ];
    }

    function getActiveAlert() {
        return buildAlert(_alertIndex);
    }

    function getNextAlert() {
        _alertIndex = (_alertIndex + 1) % 3;
        return buildAlert(_alertIndex);
    }

    function buildAlert(index) {
        return _parser.parse(_mockAlerts[index]);
    }
}
