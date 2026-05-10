# Product Vision

SKYSHIELD is intended to give field operators fast, wearable drone threat awareness without requiring them to constantly watch a phone, tablet, or detector screen.

The product is a middleware and alert-display system. It receives alerts from existing drone detector equipment, converts them into a common protocol, and pushes tactical warnings to a Garmin Enduro 2 watch.

## Core Idea

Drone detector systems vary in output format, confidence scoring, frequency reporting, and user interface quality. SKYSHIELD creates a shared alert layer that can normalize those differences and present a consistent field warning.

The operator should be able to understand the essentials quickly:

- What kind of threat is present
- How severe the threat is
- How confident the detection is
- Which band is involved
- How close the threat appears to be
- Whether the alert demands immediate attention

## System Boundaries

SKYSHIELD is not a drone detector in the MVP. It does not perform RF detection, classification from raw spectrum data, or direction finding.

The system assumes a detector layer already exists. SKYSHIELD receives alert events from that layer and handles normalization, prioritization, transport, and wearable presentation.

## Target Field Experience

The watch should communicate urgency through both visuals and haptics. The Garmin Enduro 2 acts as a tactical alert surface:

- Short readable alert labels
- Risk level and threat type
- Confidence and distance category
- Distinct vibration patterns for different severity levels
- Minimal interaction burden under stress

## Long-Term Direction

Future versions may support real detector adapters, richer event history, directional hints, mesh forwarding, team alert sharing, and multiple wearable targets.

Future compatibility targets include Chuyka, Tsukorok, SkyDroid, and custom RF detectors.
