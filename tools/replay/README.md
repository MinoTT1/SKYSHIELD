# SKYSHIELD Replay Simulator

This tool replays canonical SKYSHIELD RF telemetry packets over time.

It is intended for protocol testing, replay sessions, packet freshness testing, and future bridge development. It does not implement BLE and does not talk to Garmin directly yet.

## Files

- `replay.py`: loads a replay session and prints packets in real time
- `sample-session.json`: example timed RF telemetry sequence

## Usage

From the repository root:

```sh
python3 tools/replay/replay.py
```

With a custom session file:

```sh
python3 tools/replay/replay.py path/to/session.json
```

Output format:

```text
[00.0s]
{"threat":"FPV","severity":"HIGH","band":"5.8GHz","direction":"FRONT","distance":"NEAR","confidence":87,...}
```

## Session Format

The session file is a JSON array. Each entry has:

- `offset`: seconds from replay start
- `packet`: canonical SKYSHIELD RF telemetry payload

Packets should remain aligned with `protocol/skyshield-alert.schema.json`.

## Future BLE Path

Later, this replay tool can be extended to stream packets directly to an ESP32 BLE bridge or to a local bridge test harness.

Possible future flow:

```text
sample-session.json -> replay.py -> ESP32 bridge test transport -> BLE notify -> Garmin app
```

For now, stdout replay is enough to validate timing, packet shape, freshness behavior, and scenario design. It does not validate RF detection accuracy.
