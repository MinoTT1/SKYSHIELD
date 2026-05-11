// Simulates the future BLE connection lifecycle for the Garmin HUD.
// Future BLE callbacks can replace tick() with real state updates.
class ConnectionStateService {
    var _state;
    var _tickCount;
    var _connectedTicks;
    var _blinkOn;

    function initialize() {
        reset();
    }

    function reset() {
        _state = "SCANNING";
        _tickCount = 0;
        _connectedTicks = 0;
        _blinkOn = true;
    }

    function tick() {
        _tickCount += 1;

        if (_state == "SCANNING") {
            if (_tickCount >= 12) {
                setState("CONNECTING");
            }

            return;
        }

        if (_state == "CONNECTING") {
            if (_tickCount >= 8) {
                setState("CONNECTED");
            }

            return;
        }

        if (_state == "CONNECTED") {
            _connectedTicks += 1;

            if (_connectedTicks >= 96) {
                setState("SIGNAL_LOST");
            }

            return;
        }

        if (_state == "SIGNAL_LOST") {
            if ((_tickCount % 2) == 0) {
                _blinkOn = !_blinkOn;
            }

            if (_tickCount >= 8) {
                setState("CONNECTING");
            }
        }
    }

    function setState(state) {
        _state = state;
        _tickCount = 0;
        _blinkOn = true;

        if (state == "CONNECTED") {
            _connectedTicks = 0;
        }
    }

    function getState() {
        return _state;
    }

    function isSignalLost() {
        return _state == "SIGNAL_LOST";
    }

    function isBlinkOn() {
        return _blinkOn;
    }
}
