// Regenerates the Monkey C mock byte vectors in
// garmin-app/source/MockAlertSource.mc.
//
// The watch mocks are real CBOR packets produced by this encoder rather than
// hand-written literals, so simulator/demo data cannot drift away from the
// wire format the bridge actually emits.
//
// Run via: tools/contract-test/run.sh --emit-mocks

#include "SkyShieldCodec.h"

#include <cstdio>

using namespace skyshield;

namespace {

void emit(const char* comment, const Alert& alert) {
    uint8_t buffer[MAX_PAYLOAD_BYTES];
    const size_t length = encodeAlert(alert, buffer, sizeof(buffer));

    if (length == 0) {
        printf("            // ENCODE FAILED for %s\n", comment);
        return;
    }

    printf("            // %s\n            [", comment);

    for (size_t i = 0; i < length; i += 1) {
        printf("0x%02X%s", buffer[i], ((i + 1) < length) ? ", " : "");
    }

    printf("]b,\n");
}

void applyBands(Alert& alert, BandStrength b12, BandStrength b24,
                BandStrength b33, BandStrength b58) {
    alert.hasBands = true;
    alert.bands[0] = b12;
    alert.bands[1] = b24;
    alert.bands[2] = b33;
    alert.bands[3] = b58;
}

}  // namespace

int main() {
    Alert alert;

    printf("        _mockPackets = [\n");

    alertInit(alert);
    alert.timestampMs = 4000;
    alert.sequence = 1;
    alert.threat = THREAT_FPV;
    alert.severity = SEVERITY_HIGH;
    alert.band = BAND_5_8;
    alert.distance = DISTANCE_NEAR;
    alert.hasConfidence = true;
    alert.confidence = 87;
    alertSetDroneClass(alert, "FPV");
    applyBands(alert, STRENGTH_LOW, STRENGTH_LOW, STRENGTH_MED, STRENGTH_HIGH);
    alertSetSource(alert, "MOCK");
    emit("FPV / HIGH / 5.8GHz / NEAR / conf 87", alert);

    alertInit(alert);
    alert.timestampMs = 8000;
    alert.sequence = 2;
    alert.threat = THREAT_DJI;
    alert.severity = SEVERITY_MEDIUM;
    alert.band = BAND_2_4;
    alert.distance = DISTANCE_MID;
    alert.hasConfidence = true;
    alert.confidence = 72;
    alertSetDroneClass(alert, "MAVIC");
    applyBands(alert, STRENGTH_LOW, STRENGTH_MED, STRENGTH_MED, STRENGTH_LOW);
    alertSetSource(alert, "MOCK");
    emit("DJI / MEDIUM / 2.4GHz / MID / conf 72", alert);

    alertInit(alert);
    alert.timestampMs = 12000;
    alert.sequence = 3;
    alert.threat = THREAT_UNKNOWN;
    alert.severity = SEVERITY_CRITICAL;
    alert.band = BAND_MULTI;
    alert.distance = DISTANCE_NEAR;
    alert.hasConfidence = true;
    alert.confidence = 94;
    alertSetDroneClass(alert, "UNKNOWN");
    applyBands(alert, STRENGTH_HIGH, STRENGTH_MED, STRENGTH_MED, STRENGTH_HIGH);
    alertSetSource(alert, "MOCK");
    emit("UNKNOWN / CRITICAL / MULTI / NEAR / conf 94", alert);

    // Data-less contact, so the watch's no-classification path stays exercised
    // in the simulator.
    alertInitContact(alert, 16000, 4);
    alertSetSource(alert, "MOCK");
    emit("CONTACT: detected but unclassifiable, confidence null", alert);

    printf("        ];\n");
    return 0;
}
