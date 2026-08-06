import Toybox.Application;
import Toybox.WatchUi;

class SkyShieldApp extends Application.AppBase {
    // Read BEFORE the new session overwrites it, so the crashed session's final
    // state survives into this launch and can be shown on screen.
    var _crashReport;

    function initialize() {
        AppBase.initialize();
        BleResourceLog.markPhase(PHASE_APP_INIT, "app initialize");
        _crashReport = BleResourceLog.readCrashReport();
        BleResourceLog.markPhase(PHASE_CRASH_READ, "crash report read");
    }

    function onStart(state) {
        BleResourceLog.markPhase(PHASE_ON_START, "onStart");
    }

    // Marks a clean exit. A System Error never reaches this, which is exactly
    // how the next launch knows the previous session died.
    function onStop(state) {
        var ledger = SkyShieldApp.activeLog;

        if (ledger != null) {
            ledger.endSessionCleanly();
        }
    }

    function getCrashReport() {
        return _crashReport;
    }

    // Set by BleAlertSource so onStop can close the session without reaching
    // through the view hierarchy.
    static var activeLog;

    function getInitialView() {
        return [ new SkyShieldView(_crashReport) ];
    }
}
