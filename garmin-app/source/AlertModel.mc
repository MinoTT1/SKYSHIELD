// Normalized alert shape used by the Garmin MVP.
// Future BLE integration should populate this model from SKYSHIELD protocol JSON.
class AlertModel {
    var threatType;
    var riskLevel;
    var confidencePercent;
    var band;
    var distanceLabel;
    var activeBands;
    var directionLabel;
    var source;
    var sequence;
    var droneClass;

    function initialize(threat, risk, confidence, primaryBand, distance, bands, directionValue, sourceLabel, sequenceNumber) {
        threatType = threat;
        riskLevel = risk;
        confidencePercent = confidence;
        band = primaryBand;
        distanceLabel = distance;
        activeBands = bands;
        directionLabel = directionValue;
        source = sourceLabel;
        sequence = sequenceNumber;
        droneClass = "UNKNOWN";
    }
}
