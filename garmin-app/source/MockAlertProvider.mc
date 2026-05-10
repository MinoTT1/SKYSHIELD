// Hardcoded MVP data. No RF detection and no BLE are used in this prototype.
class MockAlertProvider {
    function initialize() {
    }

    function getActiveAlert() {
        var bands = [
            { :band => "1.2", :level => "LOW" },
            { :band => "3.3", :level => "MED" },
            { :band => "5.8", :level => "HIGH" }
        ];

        return new AlertModel(
            "FPV",
            "HIGH",
            87,
            "5.8 GHz",
            "NEAR",
            bands
        );
    }
}
