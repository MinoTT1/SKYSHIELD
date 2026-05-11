# Product Vision

SKYSHIELD is intended to give field operators fast, wearable RF situational awareness without requiring them to constantly watch a phone, tablet, or RF console.

The product is a middleware and wearable RF HUD system. It receives RF telemetry-style events from simulated sources or future adapters, converts them into a common protocol, and pushes concise awareness cues to a Garmin Enduro 2 watch.

## Core Idea

RF monitoring and detector systems vary in output format, confidence scoring, frequency reporting, and user interface quality. SKYSHIELD creates a shared telemetry layer that can normalize those differences and present consistent wearable RF awareness.

The operator should be able to understand the essentials quickly:

- What RF classification is being reported
- How elevated the RF activity appears
- How confident the classification is
- Which band is involved
- Whether the signal appears weak, moderate, or strong
- Whether the RF cue deserves attention

## System Boundaries

SKYSHIELD is not a validated RF detector in the MVP. It does not perform raw spectrum analysis, validated RF classification, precise distance estimation, or production direction finding.

The system assumes a simulated source today and future RF source adapters later. SKYSHIELD receives events from that layer and handles normalization, prioritization, transport, packet freshness, and wearable presentation.

## Target Field Experience

The watch should communicate RF activity through visuals and haptics without overstating certainty. The Garmin Enduro 2 acts as a tactical RF HUD:

- Short readable alert labels
- RF activity level and classification
- Confidence and signal-strength category
- Packet freshness and BLE health metadata
- Distinct vibration patterns for different severity levels
- Minimal interaction burden under stress

## Long-Term Direction

Near-term work should focus on BLE transport, RF awareness UX, replay tooling, telemetry workflow, and operator trust indicators.

Long-term research directions may include validated detector adapters, richer event history, experimental directional hints, mesh forwarding, team alert sharing, multiple wearable targets, AI-assisted classification, prediction, and triangulation. These are not near-term validated capabilities.

Future compatibility targets include Chuyka, Tsukorok, SkyDroid, and custom RF detectors after adapter and validation work.

## Limitations

- RSSI is not precise distance.
- RF classification remains heuristic until measured against controlled data.
- False positives are possible and expected.
- RF environments vary heavily between urban, vehicle, open-field, and indoor conditions.
- Direction estimation is experimental and should not be treated as a precise bearing.

## Detection Validation

Credible product claims require validation work:

- Field testing in repeatable scenarios
- Urban RF testing
- Open-field RF testing
- DJI experiments and controlled known-device trials where lawful and safe
- False positive measurement
- End-to-end latency measurement
- Battery runtime measurement

## Future KPIs

- Alert latency
- Packet freshness
- BLE stability
- False alert rate
- Battery runtime
- RF activity detection rate after real RF inputs are integrated
