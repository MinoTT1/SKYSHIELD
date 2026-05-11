// Hardcoded MVP data. No RF detection and no BLE are used in this prototype.
class MockAlertProvider {
    var _alertIndex;

    function initialize() {
        _alertIndex = 0;
    }

    function getActiveAlert() {
        return buildAlert(_alertIndex);
    }

    function getNextAlert() {
        _alertIndex = (_alertIndex + 1) % 3;
        return buildAlert(_alertIndex);
    }

    function buildAlert(index) {
        if (index == 1) {
            return buildDjiMediumAlert();
        }

        if (index == 2) {
            return buildUnknownCriticalAlert();
        }

        return buildFpvHighAlert();
    }

    function buildFpvHighAlert() {
        return new AlertModel("FPV", "HIGH", 87, "5.8 GHz", "NEAR", [
            { :band => "1.2", :level => "LOW" },
            { :band => "2.4", :level => "LOW" },
            { :band => "3.3", :level => "MED" },
            { :band => "5.8", :level => "HIGH" }
        ]);
    }

    function buildDjiMediumAlert() {
        return new AlertModel("DJI", "MEDIUM", 72, "2.4 GHz", "MED", [
            { :band => "1.2", :level => "LOW" },
            { :band => "2.4", :level => "MED" },
            { :band => "3.3", :level => "MED" },
            { :band => "5.8", :level => "LOW" }
        ]);
    }

    function buildUnknownCriticalAlert() {
        return new AlertModel("UNKNOWN", "CRITICAL", 94, "MULTI", "NEAR", [
            { :band => "1.2", :level => "HIGH" },
            { :band => "2.4", :level => "MED" },
            { :band => "3.3", :level => "MED" },
            { :band => "5.8", :level => "HIGH" }
        ]);
    }
}
