// Normalized alert shape used by the Garmin MVP.
// Future BLE integration should populate this model from SKYSHIELD protocol JSON.
class AlertModel {
    var threatType;
    var riskLevel;
    var confidencePercent;
    var band;
    var distanceLabel;
    var activeBands;

    function initialize(threat, risk, confidence, primaryBand, distance, bands) {
        threatType = threat;
        riskLevel = risk;
        confidencePercent = confidence;
        band = primaryBand;
        distanceLabel = distance;
        activeBands = bands;
    }
}
