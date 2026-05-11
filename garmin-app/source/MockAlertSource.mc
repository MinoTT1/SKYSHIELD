// Mock source for MVP development. It emits canonical SKYSHIELD JSON strings
// and parses them through AlertParser, matching the future BLE data path.
class MockAlertSource extends AlertSource {
    var _alertIndex;
    var _parser;
    var _mockAlerts;

    function initialize() {
        AlertSource.initialize();
        _alertIndex = -1;
        _parser = new AlertParser();
        _mockAlerts = [
            "{\"threat\":\"FPV\",\"severity\":\"HIGH\",\"band\":\"5.8GHz\",\"direction\":\"FRONT\",\"distance\":\"NEAR\",\"confidence\":87,\"bands\":{\"band_1_2\":\"LOW\",\"band_2_4\":\"LOW\",\"band_3_3\":\"MED\",\"band_5_8\":\"HIGH\"},\"source\":\"GARMIN_MOCK\",\"sequence\":1}",
            "{\"threat\":\"DJI\",\"severity\":\"MEDIUM\",\"band\":\"2.4GHz\",\"direction\":\"LEFT\",\"distance\":\"MID\",\"confidence\":72,\"bands\":{\"band_1_2\":\"LOW\",\"band_2_4\":\"MED\",\"band_3_3\":\"MED\",\"band_5_8\":\"LOW\"},\"source\":\"GARMIN_MOCK\",\"sequence\":2}",
            "{\"threat\":\"UNKNOWN\",\"severity\":\"CRITICAL\",\"band\":\"MULTI\",\"direction\":\"RIGHT\",\"distance\":\"NEAR\",\"confidence\":94,\"bands\":{\"band_1_2\":\"HIGH\",\"band_2_4\":\"MED\",\"band_3_3\":\"MED\",\"band_5_8\":\"HIGH\"},\"source\":\"GARMIN_MOCK\",\"sequence\":3}"
        ];
    }

    function getNextAlert() {
        _alertIndex = (_alertIndex + 1) % 3;
        return _parser.parse(_mockAlerts[_alertIndex]);
    }
}
