# Diagnosing the BLE Workarea Crash

**Status: OPEN. This is an instrumentation build, not a fix.**

Symptom: `System Error: Error Processing Workarea connections`, empty stack,
CIQ 6.0.0 / firmware 26.09, Enduro 2 and fenix7x. Triggered reliably by
re-flashing or resetting the ESP32 while the watch is actively connected — an
abrupt peer disappearance, not a clean disconnect.

## Why this build exists

Two fixes have been shipped on reasoning alone and **both failed on hardware**:

| Commit | Theory | Outcome |
|---|---|---|
| `2f9e1eb` | watch never reconnected | fixed a real bug, did not fix the crash |
| `4c54160` | `Ble.pairDevice()` slot never released by `unpairDevice()` | still crashes |

A third guess is not worth shipping. This build adds a resource ledger so the
next reproduction identifies the exhausted resource directly.

## What was found while instrumenting

`releasePendingDevice()` — the unpair added in `4c54160` — sits behind **two
early returns and the reconnect backoff**:

```monkeyc
function serviceReconnect() {
    if (!_reconnectPending || !_enabled) { return; }
    if (_uptimeMs < _reconnectAtMs)      { return; }   // 1-8s backoff
    ...
    releasePendingDevice();
}
```

So the unpair cannot run until at least one second after the disconnect. **If
the fault occurs at or near the disconnect instant, that fix never executed**,
which would explain why it changed nothing. The ledger settles this: if
`UNPAIR executed` never appears in the log after a disconnect, the release path
is not reached and the previous fix was untested rather than wrong.

This is stated as a *hypothesis to test*, not a conclusion.

## What the ledger records

Every BLE acquire is logged immediately **before** its call, so a fault inside
the call still leaves evidence it was attempted.

| Resource | Acquire | Release |
|---|---|---|
| Connection slot | `PAIR attempt #n` | `UNPAIR executed #n` |
| GATT profile | `PROFILE register attempt #n` | *(none exists)* |
| Scan | `SCAN on #n` | `SCAN off #n` |
| Subscription | `SUBSCRIBE requested #n` | *(implicit)* |
| Descriptor | `DESCRIPTOR lookup #n` | *(implicit)* |
| Read | `READ requested #n` | `READ callback #n` |

After every event a ledger line prints all running counts:

```text
SKYSHIELD BLERES  LEDGER t=41230 pair=2 unpair=1 PAIR_LEAK=1 prof=1/1
                  conn=2 disc=1 sub=2/2 desc=2 scan=3/2 read=1/1 src=1/0
```

**`PAIR_LEAK` is the headline figure.** If it climbs by one per connect cycle,
the connection slot is leaking. If it stays at 0 or 1 while `prof=` climbs, the
profile registration is the leak instead. If nothing climbs, the workarea is
being exhausted by something other than our own acquires, and the last `step:`
line says where.

## The crash location

The fault is instant and stackless, so **the last line printed is where it
died.** Teardown is therefore walked step by step:

```text
teardown 1: disconnect callback entered
teardown 2: error state set
teardown 3: characteristic reference cleared
teardown 4: scheduleReconnect entered
teardown 5: dead device queued for unpair
teardown 6: disconnect callback complete
```

If the log ends at `teardown 3`, the fault is in our teardown. If it reaches
`teardown 6` and dies later, the fault is in the reconnect path or inside the
stack itself, and the timestamps show how long after the disconnect.

Individual API calls are also bracketed, for example `setScanState(SCANNING)
returned` and `unpairDevice returned`, so a fault *inside* a Connect IQ call is
distinguishable from one in our own code.

## Retrieving the log from an Enduro 2

`System.println` output from a **sideloaded** app is written to a log file on the
watch's own storage. The watch mounts as a USB mass-storage volume.

1. **Before the test**, connect the watch by USB and open the volume.
2. Go to **`GARMIN/APPS/LOGS/`**.
3. **Delete or rename the existing log** so the capture is clean. The app name
   is `SKYSHIELD`, so the file is normally **`SKYSHIELD.TXT`**.
   - If that filename is not present, list the directory and take whatever is
     there — the naming varies across firmware versions. `CIQ_LOG.YML` is the
     separate system error report and is also worth capturing, because it
     records the `System Error` itself.
4. **Eject the watch properly** and unplug it. Logs are not flushed while it is
   mounted.
5. Run the reproduction below.
6. Reconnect by USB and copy **both** `SKYSHIELD.TXT` and `CIQ_LOG.YML`.

Keep the test short. Log files are size-capped and rotate, and this build is
deliberately verbose — a long session risks losing the beginning, which is the
part containing the first connect cycle.

## Reproduction

1. Power the ESP32, start the watch app, wait for a connection and at least one
   alert so the full path is exercised.
2. Note that the ledger has printed at least one `PAIR attempt #1`.
3. **Reset or re-flash the ESP32 while the watch is still connected.**
4. Let the crash happen.
5. If the watch survives, repeat the reset — the previous failure sometimes
   needed the second or third cycle, which is itself diagnostic.
6. Capture the logs as above.

## What to look for in the log

Paste the tail of `SKYSHIELD.TXT` back. The three questions it answers:

1. **Does `UNPAIR executed` appear after a disconnect?**
   No means `4c54160` never ran, and the release must move out from behind the
   backoff.
2. **Which counter climbs across connect cycles without a matching release?**
   `PAIR_LEAK` climbing points at the connection slot. `prof=` climbing points
   at profile registration, which currently has no unregister at all.
3. **What is the last line before the crash?**
   That is the faulting operation.

## Deliberately not changed

No fix is included. In particular the **profile-registration leak was not
guarded**, despite being the named next suspect, because there is not yet
evidence it is the cause and a third unverified fix would only add noise. The
ledger counts profile registrations so the next run can confirm or rule it out.

This build is purely additive logging: 40 inserted lines, none removed, no
behavioural change.
