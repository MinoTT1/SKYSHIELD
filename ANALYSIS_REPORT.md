# SKYSHIELD Codebase Audit

Audit date: 2026-08-03. Read-only analysis; no code was modified. This report stands alone — it assumes the reader has no repository access.

## A note on "ground truth"

The audit brief asked me to read `ROADMAP.md`, the JSON alert schema, and `ble-protocol.md` first, in that order, treating them as the intended design.

**`ROADMAP.md` does not exist anywhere in the repository.** There is no P0–P3 prioritized plan on disk. The closest substitutes are `docs/mvp-scope.md`, `docs/product-vision.md`, and the "Not In MVP" / "Future Work" / "Validation Roadmap" / "Future KPIs" sections scattered across `README.md`, `esp32-bridge/README.md`, `garmin-app/README.md`, and `docs/ble-gatt-design.md`. None of these use P0–P3 labels. I built the roadmap table in section 3 from these scattered sources and flagged this gap itself as a finding — a team cannot audit progress against a plan that isn't written down anywhere with priorities attached.

Worse: the JSON schema and `ble-protocol.md` turn out **not to describe what the code actually does**. See Finding A-1 below — this is the single most important discovery of the audit.

---

## 1. Executive Summary — top 5 things that matter most

1. **The documented protocol and the shipped protocol are two different things, and nobody reconciled them.** `protocol/skyshield-alert.schema.json`, `docs/ble-protocol.md`, `docs/ble-gatt-design.md`, `esp32-bridge/README.md`, `garmin-app/README.md`, `mock-data/alert-scenarios.json`, and `protocol/examples/*.json` all describe a JSON packet (`{"threat":"FPV","severity":"HIGH",...,"confidence":87,...}`). The actual firmware (`esp32-bridge/src/main.cpp:88`, `esp32-bridge/include/SkyShieldAlert.h:92`) transmits a completely different pipe-delimited format over BLE: `S2|F|H|58|N|FPV`. The Garmin app's canonical JSON parser (`AlertParser.mc`) is **never called** on real BLE traffic — a second, separate, undocumented byte-level parser in `BleAlertSource.mc` handles the real wire format instead. Top-level `README.md` and `PAYLOAD_SPEC.md` do describe S2, but they contradict five other documents that were never updated. (Finding A-1, D-1, CRITICAL)

2. **Confidence — a field the product vision calls essential — is dead on arrival for real alerts.** The S2 format was deliberately designed without a confidence field ("Confidence percentage intentionally removed," `PAYLOAD_SPEC.md:77`), yet `docs/mvp-scope.md:38` lists confidence as a required MVP field, and the Garmin HUD is built to display it prominently ("Confidence is displayed on the ALERT screen so the HUD does not imply absolute certainty," `garmin-app/README.md:151`). Since the real BLE path hardcodes confidence to `0` (`BleAlertSource.mc:759`), every real alert will show `CONF 0%` forever. (Finding D-2, HIGH)

3. **The entire detector-adapter framework is unwired dead code.** `IDetectorAdapter.h`, `TTSKW07Adapter.h`, `SkydroidAdapter.h`, `TTSKW07Parser.h`, `SkydroidParser.h`, `SkyShieldEvent.h`, and `RawSerialCapture.h` (~250 lines across 7 files) are never referenced anywhere in `esp32-bridge/src/main.cpp` or `platformio.ini` — confirmed by grep across the whole firmware source. The system is not "detector-agnostic" in any real sense yet; it is one hardcoded mock provider plus a "LIVE mode" that, per Finding C-1, isn't actually live. (Finding F-1/F-2, HIGH)

4. **"LIVE mode" doesn't talk to a live detector — it talks to itself.** `DetectorInputAdapter::readAlert()` (`esp32-bridge/include/DetectorInputAdapter.h:9-39`) parses SKYSHIELD's own internal `S2|...` notation off the Serial port, not the TTSKW07's or Skydroid's real ASCII output. Real vendor sample lines exist in `esp32-bridge/test_samples/ttskw07_raw_samples.txt` (e.g. `TTSKW07 TIME=00:00:01 TYPE=DJI_MAVIC BAND=2.4GHz ...`) and matching expected S2 output exists in `expected_s2_payloads.txt`, but **no code anywhere transforms one into the other** — the fixtures are aspirational, not executable tests. Since `MOCK_MODE = false` is the shipped default, a freshly flashed board with a real detector wired to its UART will emit nothing over BLE until a human manually types pre-normalized SKYSHIELD syntax into the serial console. (Finding C-1, CRITICAL)

5. **No latency instrumentation exists at the three points the roadmap brief calls out as a priority** (detector event received → CORE processed → watch alerted). The S2 wire format carries no timestamp field at all, so even if a real detector were wired in, there is no way to measure detector-to-BLE-TX latency, and no way to correlate it with BLE-TX-to-watch-display latency. `tools/replay/replay.py` replays canned offsets from a JSON file; it does not measure or emit real-time latency and it doesn't even speak the current S2 wire format. (Finding G-1, HIGH)

---

## 2. Findings by section

### A. Architecture

**A-1. Two incompatible protocol designs coexist in the repo, and the code implements the undocumented one, mostly. — CRITICAL**

Evidence:
- `protocol/skyshield-alert.schema.json:8-14` requires `{threat, severity, band, distance, confidence}` as JSON.
- `docs/ble-protocol.md:43-47` gives a JSON example: `{"threat":"FPV","severity":"HIGH","band":"5.8GHz",...}`.
- `docs/ble-gatt-design.md:39,46` explicitly says to "Use canonical field names from `protocol/skyshield-alert.schema.json`" with a JSON example payload.
- `esp32-bridge/README.md:53-63` and `garmin-app/README.md` (throughout) also describe the JSON shape.
- vs. `README.md:63-76` and `PAYLOAD_SPEC.md:9-18`: "Current wire format: `S2|RF_TYPE|SEVERITY|BAND|STRENGTH|DRONE_CLASS`", e.g. `S2|F|H|58|N|FPV`.
- Actual firmware: `esp32-bridge/src/main.cpp:87-96` calls `alertToBleS2(alert)` and transmits that string over the NimBLE characteristic. `esp32-bridge/include/SkyShieldAlert.h:92-104` implements `alertToBleS2`.
- Actual Garmin parsing of real BLE bytes: `garmin-app/source/BleAlertSource.mc:702-801` (`onNotificationBytes`) does hand-rolled byte scanning for the `S2|`/`S1|` marker (byte values 83,50/49,124) and pulls fields out positionally. It does **not** call `AlertParser.parse()`.
- `garmin-app/source/AlertParser.mc:79-105` only recognizes JSON tokens like `"threat":"FPV"` or the compact `"t":"F"` JSON key — neither of these appears anywhere in a real S2 payload. `AlertParser` is only ever invoked by `MockAlertSource.mc:19-22`, i.e. it is exercised solely by the mock rotation, never by anything a real ESP32 sends.

Impact: The schema file and three of the protocol docs describe a wire format the system does not actually use for its live path. Anyone who implements a new detector adapter, a new BLE client, or an interop test against `protocol/skyshield-alert.schema.json` will build something incompatible with the real firmware. There is no schema, validator, or test tying the two together — the drift can (and evidently did) happen silently.

Fix (describe, don't implement): Pick one canonical wire format and delete the other. If S2 is the intended direction (it looks like the more recent design, given git history — `Use simple BLE wire payload on ESP32` postdates the JSON-era commits), update `protocol/skyshield-alert.schema.json`, `docs/ble-protocol.md`, `docs/ble-gatt-design.md`, both sub-project READMEs, `protocol/examples/*.json`, and `mock-data/alert-scenarios.json` to describe S2 instead of JSON, and delete `AlertParser.mc`'s dead JSON-parsing path (or repurpose `MockAlertSource` to emit S2 strings through the *same* parser `BleAlertSource` uses, so there's only one implementation of "how to read an alert").

**A-2. The detector-adapter abstraction (`IDetectorAdapter`) is not used by the code path that claims to support live detectors.**

`esp32-bridge/include/IDetectorAdapter.h` defines a clean `init/connect/disconnect/poll` interface. `TTSKW07Adapter.h` and `SkydroidAdapter.h` implement it. But `main.cpp` doesn't hold a `IDetectorAdapter*` anywhere; it instantiates a concrete `DetectorInputAdapter` (`main.cpp:9`) that implements none of these interfaces and has its own bespoke `readAlert()` method. See C-1/F-1 for the functional consequence.

### B. Bugs & Correctness

**B-1. Real BLE alerts always carry `confidence = 0` and `sequence = 0`. — HIGH**

`BleAlertSource.mc:759-783`: for an `S2` payload, `confidence` is left at its initialized value `0` (only legacy/unused `"S1"` payloads compute a numeric confidence via `confidenceFromBytes`), and the `AlertModel` is constructed with the literal `0` as the sequence argument. Since `docs/ble-protocol.md:84` documents `sequence` as the mechanism for the watch to "ignore duplicate packets," and the schema documents `confidence` as a core field, both are effectively non-functional for the shipping data path. See Executive Summary #2.

**B-2. `getLastRawPayload()` always returns the literal string `"S1"`, not the actual bytes received. — MEDIUM**

`BleAlertSource.mc:791`: `_lastRawPayload = "S1";` is a hardcoded string literal, not derived from `bytes`. Any operator/debug UI that surfaces `getLastRawPayload()` for troubleshooting a real BLE session will see the wrong value regardless of what was actually transmitted (it will say "S1" even when a valid "S2" packet was received). This looks like a leftover placeholder from development rather than intentional behavior.

Fix: capture the decoded string (e.g., via `bytesToUtf8String(bytes)` or a raw substring around the parsed marker) before assigning to `_lastRawPayload`.

**B-3. `getPacketAgeLabel()` has an effectively-dead branch due to condition ordering. — LOW**

`garmin-app/source/SkyShieldView.mc:891-898`:
```
if (_packetAgeMs > STALE_PACKET_MS) { return "STALE"; }
if (_packetAgeMs >= STALE_PACKET_MS) { return "10s"; }
```
Because the first branch already catches everything `> STALE_PACKET_MS`, the second branch can only ever fire on the single exact tick where `_packetAgeMs == STALE_PACKET_MS` (10000ms, incrementing in 250ms steps per `updatePacketAge()` at line 390-394) — a one-in-forty-tick coincidence that produces a flash of `"10s"` before the next tick shows `"STALE"`. Confusing, not exactly wrong, but almost certainly not the intended behavior.

Fix: swap the comparison so the boundary case is `==`, or just delete the redundant second branch.

**B-4. `Serial.readStringUntil('\n')` can block the whole firmware loop for up to its default 1s timeout. — MEDIUM**

`esp32-bridge/include/DetectorInputAdapter.h:18-23`: the check `Serial.available()` only guarantees at least one byte is present, not a full line. If a partial line (no trailing `\n`) sits in the buffer — plausible with a noisy/partial real detector feed, or the `NOISE UART FRAME DROPPED 0x00 0xFF` line seen in `test_samples/ttskw07_raw_samples.txt` — `readStringUntil` will block the Arduino main loop for up to its timeout (default 1000ms) on every such call. Since NimBLE housekeeping and the alert-interval scheduling both run from the same `loop()`, this stalls BLE connection maintenance and the 4-second alert cadence simultaneously.

Fix: use a non-blocking, bounded line reader (the already-written but unused `RawSerialCapture` class does exactly this correctly) instead of `readStringUntil`.

**B-5. `_droneClass` is a single reused member buffer with implicit lifetime coupling. — LOW**

`DetectorInputAdapter.h:42,88-100`: `NormalizedAlert.droneClass` is a raw `const char*` pointing at the adapter's private `_droneClass[24]` buffer, which is overwritten on every `readAlert()` call. This works today only because `publishNormalizedAlert()` (`main.cpp:87-110`) always serializes the string immediately and doesn't hold the `NormalizedAlert` across two poll cycles. Any future refactor that buffers/queues alerts (e.g., for the "recent-alert cache" the docs call for — see E-3) will silently corrupt `droneClass` on the next detector line. Worth a comment or, better, switching to a fixed-size copy embedded directly in `NormalizedAlert`.

### C. Unfinished / Stubbed

**C-1. "LIVE mode" is not live — it replays SKYSHIELD's own internal wire format, not real detector output. — CRITICAL**

See Executive Summary #4 for the core evidence. To spell out the mechanism: `DetectorInputAdapter::expandShortcut()` (`DetectorInputAdapter.h:44-62`) maps typed words like `FPV`/`MAVIC`/`AUTEL`/`UNKNOWN` to hardcoded `S2|...` strings, and `parseS2Line()` (`DetectorInputAdapter.h:64-103`) parses the bridge's *own output format* back in as if it were detector input. This is a serial-console test harness for a human operator, mislabeled in the code (`modeLabel()` at `main.cpp:26-28` prints `"LIVE"`) and in the README ("LIVE mode active, waiting for detector input," `main.cpp:167`) as if it consumes real sensor data.

**C-2. `TTSKW07Adapter`/`SkydroidAdapter` are pure stubs; `TTSKW07Parser`/`SkydroidParser` only match a string prefix. — HIGH**

`esp32-bridge/include/TTSKW07Adapter.h:7-33` — every method (`init`, `connect`, `poll`) is a no-op returning `false` or nothing, with only comments describing "future" behavior.
`esp32-bridge/include/TTSKW07Parser.h:27-31` — `parseLine()` does nothing but check `trimmed.startsWith("TTSKW07")` and returns `true`/`false`; no field extraction occurs despite the vendor-confirmed real sample format already existing in `test_samples/ttskw07_raw_samples.txt` (`TTSKW07 TIME=00:00:01 TYPE=DJI_MAVIC BAND=2.4GHz FREQ_MHZ=2437 RSSI=-61DBM SIGNAL=MID`). Same pattern for `SkydroidAdapter.h`/`SkydroidParser.h`.
Confirmed dead: `grep -rn "TTSKW07Adapter\|SkydroidAdapter\|TTSKW07Parser\|SkydroidParser\|IDetectorAdapter\|RawSerialCapture" esp32-bridge/src/` returns nothing — none of these seven files is referenced from the actual firmware `.cpp`.

**C-3. Test fixtures exist with no test harness that runs them.**

`esp32-bridge/test_samples/ttskw07_raw_samples.txt` (5 realistic vendor lines + 1 noise/garbage line) and `expected_s2_payloads.txt` (the corresponding expected S2 output) look like they were written to drive a unit test for `TTSKW07Parser`, but no such test exists in the repo (no `test/` directory, no `pio test` environment in `platformio.ini`). These are inert data files today.

**C-4. `RawSerialCapture` is a fully-correct, unused implementation.**

`esp32-bridge/include/RawSerialCapture.h` implements exactly the non-blocking, bounded (160-char), whitespace-trimmed line buffering that `DetectorInputAdapter` actually needs (see B-4) but doesn't use. It's dead code sitting next to the bug it would fix.

### D. Protocol & Schema

**D-1. The code does not emit/consume the documented schema for real traffic.** Restating A-1 with the schema-specific angle: `protocol/skyshield-alert.schema.json` is `additionalProperties: false` and requires `threat/severity/band/distance/confidence` as a JSON object — the real BLE payload is not JSON at all, so no JSON-schema validator could ever be run against real traffic without first writing a translation layer that doesn't currently exist.

**D-2. `protocol_version` is absent everywhere.** Neither the JSON schema, nor `docs/ble-protocol.md`, nor the S2 format (`PAYLOAD_SPEC.md`), nor any `.mc`/`.h`/`.cpp` file contains a `protocol_version` field (confirmed via repo-wide grep). The closest thing is the informal `S2`/`S1` marker byte in `BleAlertSource.mc:754` (`bytes[startIndex+1] == 50` for '2'), which is a version discriminator in spirit but is undocumented, has no defined `S1` format anywhere in the docs, and isn't exposed as a distinct protocol field the way the audit brief's "P0 requires it" framing implies. **Status: NOT DONE.**

**D-3. No defined path for a data-less "contact" alert (unknown threat/band, low confidence).** The closest analog is `threat=UNKNOWN` + `band=MULTI`/`X` (used for the mock "unknown-critical" scenario, which is actually *high*-confidence, not low-confidence). There is no documented or implemented alert shape for "something triggered but we don't know what/where/how sure" — i.e., a genuine low-information contact report. `AlertParser.mc:63-77`'s `fallbackAlert()` produces `UNKNOWN/LOW/0%/MULTI/FAR` but only as an *error path* when parsing fails, not as an intentional protocol state a detector could legitimately emit. **Status: NOT STARTED.**

### E. BLE Layer

**E-1. Transport is notify-only, single characteristic, no polling fallback.** `esp32-bridge/src/main.cpp:71-74` creates one characteristic with `READ | NOTIFY`. `garmin-app/source/BleAlertSource.mc:628-655` subscribes via CCCD write. This matches `docs/ble-gatt-design.md`'s design and is reasonable for the MVP.

**E-2. No MTU/fragmentation handling, but also no current need for it.** S2 payloads are tiny (`S2|F|H|58|N|FPV` ≈ 17 bytes), well under default BLE MTU (20-23 bytes payload for unnegotiated ATT_MTU). `docs/ble-gatt-design.md:41` anticipates this ("If packet size becomes too large later, add explicit chunking") but no chunking exists, which is fine *today* but will break silently the moment a payload (e.g., a future JSON-with-direction-and-bands packet, or the currently-documented-but-unshipped full JSON envelope) exceeds one notification's capacity — there is no length check or truncation guard anywhere in `main.cpp`'s `publishNormalizedAlert()`.

**E-3. "Recent-alert cache" for reconnect recovery is minimal — a single last-value GATT read, not a real cache.** `docs/hardware-notes.md:31` and `docs/ble-protocol.md:91` call for "a short recent-alert cache so the Garmin app can recover current state after reconnecting." The only mechanism present is that `alertCharacteristic->setValue()` (`main.cpp:96-99`) is called on every publish and the characteristic has the `READ` property, so a reconnecting client could issue an explicit read to get the *single* most recent alert. There is no multi-entry cache, and nothing in `BleAlertSource.mc` actually performs an explicit characteristic *read* on reconnect — it only re-subscribes and waits for the next notify. **Status: PARTIAL, and the "recovery" half of it isn't actually exercised by the watch code.**

**E-4. `expires_in_ms` is not implemented anywhere on the transport or the watch.** It exists only in `mock-data/alert-scenarios.json` (values 10000-20000ms, varying by severity) — a document that itself belongs to the abandoned JSON protocol design (A-1). `AlertModel.mc` has no field for it, `AlertParser.mc` never parses it, and `BleAlertSource.mc`'s S2 byte parser has no field for it either (the S2 format has no expiry field at all). Staleness on the watch is instead driven purely by a local wall-clock heuristic: `STALE_PACKET_MS = 10000` (`SkyShieldView.mc:17`), i.e., "no new packet for 10 real seconds," which is a reasonable client-side fallback but is not the same thing as respecting a server-declared per-alert TTL, and cannot express "this specific alert is only valid for 20 more seconds because it's a fast-moving FPV" vs. "this DJI alert is valid for a full 2 minutes." **Status: NOT STARTED** (this is explicitly listed as an MVP-optional field in `docs/mvp-scope.md:47`, so it is "optional-not-done" rather than a broken required feature — but worth flagging since the brief calls it out specifically).

**E-5. LINK LOST behavior is implemented and reasonably thorough on both sides.** Firmware: `SkyShieldServerCallbacks::onDisconnect` (`main.cpp:40-46`) restarts advertising immediately. Watch: `BleAlertSource.mc` tracks granular states (`SCANNING/CONNECTING/CONNECTED/DISCONNECTED/SIGNAL_LOST`) with per-stage timeouts (`BLE_STAGE_TIMEOUT_MS = 20000`, `tick()` at lines 179-204) and the view layer has its own independent `LINK LOST` operational state (`SkyShieldView.mc:485-497`, `LIVE_ALERT_MS=5000`) that degrades from "LIVE" to whatever the BLE layer reports. This is one of the more mature parts of the codebase — reconnect does restart scanning (`startScan()` guards at `BleAlertSource.mc:341-377`).

### F. Adapter Framework

**F-1. Not genuinely detector-agnostic — it's one hardcoded mock plus a self-referential "live" mode.** See C-1, C-2, A-2. The `IDetectorAdapter` interface is a reasonable design (`init/connect/disconnect/poll`), but nothing in the running firmware ever calls through it. `MockAlertProvider` (`esp32-bridge/include/MockAlertProvider.h:41-45`) hardcodes exactly 3 alerts as static const data.

**F-2. TTSKW07 adapter state: skeleton only, matching the docs' own caveat.** `docs/TTSKW07_INTEGRATION_PLAN.md:47-51` explicitly says "The exact ASCII line format is still unknown... Update `TTSKW07Parser` only after the real format is captured," and indeed the parser is unimplemented (C-2). To its credit, the vendor-confirmed parameters (115200 8N1, ASCII, fields: detection time/drone type/band/signal strength — `docs/TTSKW07_INTEGRATION_PLAN.md:9-22`) match what the audit brief describes, and realistic sample data already exists (C-3) — the remaining work is well-scoped, just not started.

**F-3. Skydroid adapter: same skeleton state, plus zero robustness against partial/malformed lines by design (not yet applicable since nothing parses real data).** No buffering/framing exists for either adapter's *intended* real input — only `RawSerialCapture` (currently unused, C-4) would provide it.

### G. Latency Instrumentation

**G-1. No timestamps exist at any of the three required measurement points. — HIGH, flagged as a priority per the audit brief.**
- Detector-event-received: no timestamp is captured anywhere a real detector line would be read (`DetectorInputAdapter::readAlert`, `main.cpp:133-145` `pollLiveDetector()`) — no `millis()` call at ingestion.
- CORE-processed: `main.cpp`'s `publishNormalizedAlert()` (line 87) doesn't timestamp itself either; the only timing data on the firmware side is the coarse `lastAlertMs`/`ALERT_INTERVAL_MS` scheduling loop, not per-alert processing latency.
- Watch-alerted: `BleAlertSource.mc` *does* do fine-grained internal timing (`logTiming()` calls at lines 574, 676-677, 698 measuring connect→subscribe→notification intervals), but this only measures **BLE session/connection lifecycle timing**, not "time from alert generation to watch display" — and none of it can be correlated back to a detector event because no timestamp travels in the payload (the S2 format has no timestamp field, `SkyShieldAlert.h:5-16` and `alertToBleS2`, `SkyShieldAlert.h:92-104`).
- `tools/replay/replay.py` prints packets at scripted offsets read from a static JSON session file (`sample-session.json`) using `time.sleep()` between them — it does not capture wall-clock timestamps of an actual event, and it emits the old JSON envelope (from `load_session`'s expectation of an `{"offset":..., "packet": {...}}` shape matching the abandoned JSON design), not S2. It cannot currently be used to measure real transport latency end-to-end.

Fix (describe): add a `timestampMs` (or similar) field to the wire format at the point of generation (either in the detector-adapter layer or right before BLE TX), have the watch record its own receipt timestamp in `handleCharacteristicChanged`/`onNotificationBytes`, and log the delta. This requires either extending S2 with a numeric field or moving to a slightly richer format — a deliberate protocol decision that should be made once, not accreted piecemeal (tying back to A-1).

### H. Robustness, Security, Resources

**H-1. No BLE encryption or pairing policy.** Explicitly acknowledged as out of scope in `docs/ble-gatt-design.md:123` ("No encryption yet") and `esp32-bridge/README.md:142` ("BLE is unencrypted and intended for MVP validation only"). `Ble.pairDevice()` (`BleAlertSource.mc:549`) may trigger OS-level bonding depending on the Connect IQ BLE stack's defaults, but nothing in the code explicitly requests or verifies an encrypted link. Acceptable for a documented MVP, but should be tracked as a pre-field-deployment blocker given this is a security/situational-awareness product.

**H-2. Heap/memory on ESP32.** The firmware makes heavy use of Arduino `String` (`SkyShieldAlert.h`'s `alertToBleS2`/`alertToJson`/`normalizedAlertSummary` all build `String` objects via repeated `+=`), which is known to fragment heap over long uptimes on ESP32. For a device meant to run continuously in the field, this is a real long-term-stability risk, though not likely to manifest in short test sessions. `RawSerialCapture` by contrast uses fixed-size char buffers correctly (ironic, since it's unused — C-4).

**H-3. Connect IQ memory.** No explicit budget/limits analysis exists in the docs or code; `BleAlertSource.mc` alone is 1371 lines with many string-literal constants (likely interned, low actual RAM cost) and no obviously unbounded collections. `AlertHistory` (`AlertHistory.mc:9-14`) is a correctly fixed-size 5-slot ring buffer — good practice.

**H-4. No battery/power handling code exists anywhere**, despite being called out repeatedly as a "Future KPI" in `README.md:123`, `mvp-scope.md:106`, `hardware-notes.md`. The planned `Status` characteristic (`docs/ble-gatt-design.md:58-69`, fields `battery`/`state`/`detector`/`uptime_ms`) is not implemented in `main.cpp` at all — only the Alert characteristic exists. This is consistent with the docs' own "Not In MVP" framing, so it's an honest gap, not a silent one.

**H-5. Graceful degradation is one of the stronger areas.** The watch's operational-state machine (`SkyShieldView.mc:485-497`) degrades cleanly from LIVE → MONITOR → LINK LOST, and the firmware re-advertises immediately on disconnect (`main.cpp:44-46`). This part of the system was clearly iterated on carefully (commit history shows dedicated passes: "Stabilize failsafe monitor live link states," "Stabilize UI-synchronized tactical haptic engine").

### I. Code Quality

**I-1. Significant duplication of S2 encode/decode logic across three independent implementations** that must be kept in sync by hand: (1) `SkyShieldAlert.h`'s `compactThreat/compactSeverity/compactBand/compactDistance` (encode, firmware→wire), (2) `DetectorInputAdapter.h`'s `mapRfType/mapSeverity/mapBand/mapStrength` (decode, wire→firmware, for the "LIVE mode" self-referential path), and (3) `BleAlertSource.mc`'s `threatFromByte/severityFromByte/bandFromBytes/distanceFromByte` (decode, wire→watch). Any change to the S2 letter/number codes (e.g., adding a new band) requires touching three hand-written mapping tables in two languages with no shared source of truth or test.

**I-2. Dead code beyond the adapter framework (C-2/C-4):** `SkyShieldAlert.h`'s `alertToJson`, `alertToBleJson`, and `alertToBleSimple` functions (lines 34-78) are never called from `main.cpp` (only `alertToBleS2` and `normalizeAlert`/`normalizedAlertSummary` are used, per the earlier grep). `MockAlertProvider.mc` is a 6-line "backward-compatible alias" for `MockAlertSource` — check whether anything still needs it.

**I-3. Naming is generally consistent and readable**; Monkey C files favor small, single-purpose classes (`TacticalActionEngine`, `DisplayFormatter`, `ConnectionStateService`) with clear separation of "raw protocol value" vs. "user-facing label," which is a genuinely good pattern (`DisplayFormatter.mc:1-2`'s header comment states the rule explicitly and the rest of the codebase respects it).

**I-4. No automated tests exist for either the firmware or the Garmin app.** `test_samples/` (C-3) is the only test-shaped artifact in the repo, and nothing executes it. No PlatformIO `test/` environment, no Monkey C unit tests (Connect IQ SDK does support a test framework).

**I-5. Repo hygiene: generated build artifacts are tracked in git despite `.gitignore` intending to exclude them.** `git ls-files` shows `garmin-app/gen/no-device/source/Rez.mcgen` and `garmin-app/internal-mir/Rez.mir` are tracked, even though `.gitignore` lists `gen/` and `internal-mir/` — these were presumably committed before the ignore rules were added, and `.gitignore` doesn't retroactively untrack them. Also, `garmin-app/external-mir/Users/milankrcho/AI_WORK/SKYSHIELD/garmin-app/source/*.mir` bakes the local absolute developer path into generated filenames — a minor but real information leak / repo-hygiene issue if this repo is ever shared.

---

## 3. Roadmap Status Table

Since no `ROADMAP.md` exists, this table is built from the audit brief's explicit priority callouts plus the "Not In MVP" / "Future Work" / "Validation Roadmap" sections in the docs that actually exist. Treat "priority" as inferred, not sourced from a written plan.

| Item | Inferred Priority | Status | Evidence |
|---|---|---|---|
| Universal alert schema / canonical protocol | P0 | **PARTIAL — and drifted** | Schema file exists (`protocol/skyshield-alert.schema.json`) but describes a format the shipping code doesn't use (Finding A-1/D-1) |
| `protocol_version` field | P0 (per audit brief) | **NOT DONE** | No field anywhere in schema, docs, or code (D-2) |
| Data-less "contact" alert path | P0 (per audit brief) | **NOT STARTED** | No such concept exists; `fallbackAlert()` is an error path, not a designed feature (D-3) |
| BLE notify transport, ESP32↔Garmin | P0/P1 | **DONE** (for the S2 format) | `main.cpp:71-107`, `BleAlertSource.mc:702-801` — working, exercised, has real debug logging |
| BLE reconnect / LINK LOST handling | P1 | **DONE** | E-5 |
| Recent-alert cache for reconnect recovery | P1 | **PARTIAL** | Single last-value GATT read only, not exercised on reconnect (E-3) |
| `expires_in_ms` handling on the watch | Optional (per `mvp-scope.md`) | **NOT STARTED** | E-4 |
| Detector-agnostic adapter framework | P1 | **NOT STARTED (scaffolding only)** | F-1, C-2 — interface exists, zero live wiring |
| TTSKW07 adapter | P1 (vendor-confirmed candidate per `DETECTOR_COMPATIBILITY_MATRIX.md`) | **NOT STARTED** | C-2, though sample data + plan docs are solid groundwork |
| Skydroid S12 adapter | P2 (hardware incoming) | **NOT STARTED** | C-2 |
| Latency instrumentation (3-point) | P0 (per audit brief) | **NOT STARTED** | G-1 |
| Garmin tactical HUD (ALERT/BANDS screens) | P0/P1 | **DONE** | `SkyShieldView.mc`, confirmed by both READMEs' "Project Status" claims and by reading the rendering code |
| Vibration patterns | P1 | **DONE** | `VibrationEngine.mc` — rate-limited, severity-scaled, implemented |
| Alert history (watch-side) | P2 | **DONE (implemented, not in main rotation)** | `AlertHistory.mc`, retained in code per `garmin-app/README.md:97,115` but not part of automatic screen cycle |
| Status/Config BLE characteristics | P2 | **NOT STARTED** | H-4; designed in `docs/ble-gatt-design.md` but absent from `main.cpp` |
| BLE encryption/pairing policy | P2/P3 | **NOT STARTED** | H-1 |
| Battery/power measurement | P3 | **NOT STARTED** | H-4 |
| Automated tests (firmware or watch) | Should be P0/P1 but isn't tracked at all | **NOT STARTED** | I-4, C-3 |
| Real RF detection / validated classification | P3 (explicitly out of scope for MVP) | **NOT STARTED (by design)** | Repeated across every doc's "Limitations"/"Excluded" section |

---

## 4. New Gaps Not In Any Existing Doc

1. **No document reconciling the JSON-schema design with the S2 design.** This is the single highest-leverage fix available — right now two designs exist and a newcomer has no way to know which one is real without reading source code (which is what this audit had to do).
2. **No schema/contract test** that would catch protocol drift automatically (e.g., a small script that feeds `protocol/examples/*.json` through the parser and asserts round-trip correctness, or equivalently for S2). Given the drift already happened once, it will happen again without one.
3. **No CI at all** — no `.github/workflows`, no PlatformIO test env, no Monkey C test target. Combined with #2, nothing would have caught A-1 before it shipped.
4. **`_lastRawPayload` diagnostic bug (B-2)** — not previously flagged anywhere; would mislead anyone debugging a field issue via this value.
5. **Blocking serial read risk (B-4)** on the one hardware path (`DetectorInputAdapter`) that's actually wired into `main.cpp`.
6. **Repo hygiene**: tracked generated artifacts + leaked absolute local path in `external-mir` (I-5).

---

## 5. Prioritized Recommended Next Steps

**P0 — do first, blocks everything else being trustworthy:**
1. Resolve the JSON-vs-S2 protocol split (A-1/D-1). Pick one, delete/rewrite the other's docs and dead code, and make `protocol/skyshield-alert.schema.json` (or its S2 equivalent) the actual source of truth checked by a test.
2. Add `protocol_version` and a real timestamp field to whichever format wins (D-2, G-1) — do these together since both require touching the wire format once; don't make two separate breaking changes.
3. Design and implement the data-less "contact" alert path (D-3) as a first-class protocol state, not an error fallback.
4. Fix `DetectorInputAdapter` so "LIVE mode" actually reads real detector output, or rename/relabel it clearly as a serial test-injection tool until it does (C-1) — this is actively misleading as shipped.

**P1 — needed before any real detector integration:**
5. Wire `IDetectorAdapter` into `main.cpp` for real, then implement `TTSKW07Parser` against the existing captured sample data (C-2/C-3/F-2) and write the test that was clearly intended (`test_samples/`).
6. Replace `Serial.readStringUntil` with the already-written `RawSerialCapture` (B-4/C-4) to remove the blocking-read risk before any real hardware is attached.
7. Decide whether `confidence` is actually part of the product or not (B-1/D-2's sibling issue) — right now the docs and the wire format disagree, and the HUD is built around a field that will always read 0.

**P2 — hardening once the above is real:**
8. Implement the Status/Config BLE characteristics already designed in `docs/ble-gatt-design.md` (H-4), at minimum for battery and detector-connection state.
9. Add a BLE pairing/encryption policy decision (H-1) — even a documented "we accept plaintext until X" is better than silence.
10. De-duplicate the three independent S2 encode/decode implementations (I-1) into one shared definition per platform (can't share code across C++/Monkey C, but can share a single spec/test fixture both sides are tested against).

**P3 — quality-of-life / long-tail:**
11. Fix the `getPacketAgeLabel` dead branch (B-3), the `_lastRawPayload` bug (B-2), and clean up confirmed-dead functions (`alertToJson`, `alertToBleJson`, `alertToBleSimple`, `MockAlertProvider.mc`) (I-2).
12. Clean up repo hygiene: untrack the already-committed generated files, confirm `external-mir` isn't leaking local paths going forward (I-5).
13. Stand up minimal CI (PlatformIO build + a Python or shell script that validates `test_samples/` against whatever parser exists) so drift like Finding A-1 gets caught automatically next time.
