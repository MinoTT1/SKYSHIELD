import Toybox.Application;
import Toybox.WatchUi;

class SkyShieldApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new SkyShieldView() ];
    }
}
