// Simple in-app settings placeholder for future Garmin settings UI.
// Defaults are intentionally conservative for the MVP.
class SettingsModel {
    var vibrationEnabled;
    var sensitivity;
    var silentMode;

    function initialize() {
        vibrationEnabled = true;
        sensitivity = "NORMAL";
        silentMode = false;
    }
}
