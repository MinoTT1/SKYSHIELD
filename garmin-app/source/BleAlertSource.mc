// Placeholder for future BLE alert ingestion.
// Future flow:
// 1. Receive UTF-8 JSON payload from ESP32 BLE notify characteristic.
// 2. Pass the payload to AlertParser.parse().
// 3. Return the resulting AlertModel to AlertEngine.
//
// This source is intentionally not used in the MVP yet.
class BleAlertSource extends AlertSource {
    var _parser;

    function initialize() {
        AlertSource.initialize();
        _parser = new AlertParser();
    }

    function getNextAlert() {
        return null;
    }
}
