// Normalized alert shape used by the Garmin HUD.
//
// Populated only by CborAlertDecoder, which is the single place a wire packet
// becomes an AlertModel. See docs/wire-protocol.md.
class AlertModel {
    var threatType;
    var riskLevel;

    // Null when the detector reported no confidence. Null is NOT 0: it means
    // "no data", and the HUD must render it as such rather than as 0%.
    var confidencePercent;

    var band;
    var distanceLabel;
    var activeBands;
    var directionLabel;
    var source;
    var sequence;
    var droneClass;

    // "CLASSIFIED" or "CONTACT". A contact alert is a real detection that the
    // detector could not classify, not a parse failure.
    var alertKind;
    var sensorType;

    // CORE monotonic ms since bridge boot, sampled just before BLE TX.
    // Not wall-clock; see docs/wire-protocol.md.
    var timestampMs;

    // Exact detector-to-CORE latency in ms, measured in CORE's clock domain.
    // Null when the alert did not originate from a detector line.
    var detectorLatencyMs;

    // False when the bridge omitted per-band detail. The BANDS screen shows
    // UNKNOWN in that case instead of synthesizing levels.
    var hasBandDetail;

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
        alertKind = "CLASSIFIED";
        sensorType = "RF";
        timestampMs = 0;
        detectorLatencyMs = null;
        hasBandDetail = false;
    }

    function isContact() {
        return (alertKind != null) && alertKind.equals("CONTACT");
    }

    function hasConfidence() {
        return confidencePercent != null;
    }

    // Confidence for threshold comparisons. Absent confidence must never read
    // as a high value, so it floors to 0 for ranking purposes only -- display
    // code must use hasConfidence() and show "--" instead.
    function confidenceOrZero() {
        if (confidencePercent == null) {
            return 0;
        }

        return confidencePercent;
    }
}
