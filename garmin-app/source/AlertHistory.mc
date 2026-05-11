// Fixed-size alert history for the Garmin MVP.
// Uses sequence numbers instead of wall-clock time to keep the watch code simple.
class AlertHistory {
    var _records;
    var _writeIndex;
    var _count;
    var _nextSequence;

    function initialize() {
        _records = [ null, null, null, null, null ];
        _writeIndex = 0;
        _count = 0;
        _nextSequence = 1;
    }

    function addAlert(alert) {
        if (alert == null) {
            return;
        }

        _records[_writeIndex] = {
            :sequence => _nextSequence,
            :threat => alert.threatType,
            :severity => alert.riskLevel,
            :band => alert.band,
            :distance => alert.distanceLabel,
            :confidence => alert.confidencePercent
        };

        _writeIndex = (_writeIndex + 1) % 5;
        _nextSequence += 1;

        if (_count < 5) {
            _count += 1;
        }
    }

    function size() {
        return _count;
    }

    function getRecordAt(offset) {
        if (offset >= _count) {
            return null;
        }

        var index = _writeIndex - 1 - offset;

        while (index < 0) {
            index += 5;
        }

        return _records[index];
    }
}
