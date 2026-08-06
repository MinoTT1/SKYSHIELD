# Diagnosing the BLE Workarea Crash

**Status: root cause identified as a general re-entrancy rule. Pending re-test.**

## The pattern across all three crashes

| Readout | Died at | Cause |
|---|---|---|
| `c2 d0 s2` | `READ callback #2` | duplicate CONNECTED re-ran discover/subscribe/read |
| `c1 d0 s1 rd0/0 DUP=0` | `SUBSCRIBE success #1` | see below |

The second readout is a **clean first connection** — one connect, no disconnect,
no duplicate, the state-recovery read never even issued. It died immediately
after a *successful* subscribe.

Reading the subscribe-success handler, **there are no BLE calls after
`subscribeSucceeded()`** — only state assignment and logging. The one heavyweight
system call in that path was `persist()`, which did three
`Application.Storage.setValue()` flash writes **from inside the BLE callback**.

That is almost certainly the instrumentation itself. The risk was flagged when
the ledger was added ("this build writes to flash inside BLE callbacks... if the
crash becomes intermittent or moves, that is itself a finding"), and the crash
moving to every ledger event is consistent with it.

### The general rule

Every crash in this area has been the same class: **a system operation issued
from inside a BLE callback.** Pairing, discovery, CCCD writes, characteristic
reads and now flash writes.

The fix is structural rather than another point guard:

1. **Storage writes are deferred.** `persist()` only marks state dirty;
   `flush()` writes, and is called from the timer tick. Cost: a crash can lose up
   to one tick (250ms) of events. Accepted, because a diagnostic that changes the
   failure it measures is worse than one that is slightly coarse.
2. **Post-connect BLE work is deferred.** The connected callback records intent
   and returns; a queued action serviced from the timer tick performs discovery,
   the CCCD write and the state read. Each action re-validates the link at the
   moment of use, since it may have gone away while queued.

### The one deliberate exception

`handleScanResults()` still calls `setScanState(OFF)` and `pairDevice()` directly.
This is left alone on purpose:

- it demonstrably works — every readout shows `c1`/`s1` reaching a live link
- a `ScanResult` is not guaranteed to stay valid across ticks, so deferring the
  pairing risks breaking connection outright
- no evidence implicates it

Changing it would be a speculative fix with functional risk, which is the pattern
that already failed twice here. If evidence points there, it is the next thing to
defer.

The instrumentation worked. The on-screen readout from a reproduced crash:

```text
PREV SESSION CRASHED
session #1
LEDGER
P1/U0  LEAK=1  prof1/1
c2 d0 s2 sc1/1
DIED AT
pairDevice returned
READ callback #2
```

### What it actually says

**`c2 d0` is the whole answer: two CONNECTED callbacks, zero disconnects.**

When the peer vanished the stack did not report a disconnect at all. It
delivered a **second CONNECTED callback** for a link that was already gone.
`handleConnectedStateChanged()` had no idempotency guard, so that duplicate
re-ran the entire chain -- discover service, discover characteristic, look up
descriptor, subscribe, issue the state-recovery read -- against a dead peer.
`READ callback #2` came back on that second, doomed read and took the app down.

This also explains why the previous round of guards changed nothing. **Every one
of them tested `explicitDisconnectSeen`, and with `d0` that flag was never set.**
The guards were inert: they defended against a teardown that never happened.

### Two corrections to the earlier reading

- **`LEAK=1` is not a leak.** With `d0`, one pair and no disconnect means one
  connection was simply still open. That is normal. The workarea slot theory
  behind `4c54160` is unsupported by this data, and the crash happened on the
  first cycle, well before any reconnect could exhaust anything.
- **There was no "teardown".** The fault occurred on a live-looking connection
  being set up a second time, not during a disconnect sequence.

### The fix

1. **Idempotent CONNECTED handling.** A second CONNECTED while already connected
   with a characteristic in hand is logged and ignored. Re-running discovery on
   an established link cannot help; we already hold the characteristic.
2. **The state-recovery read is one-shot per connection** and is now issued from
   the timer tick rather than from inside `handleDescriptorWrite()`. Calling back
   into the BLE stack from within its own callback is what put a read in flight
   while the peer was disappearing.
3. **The read callback is hardened**: the value buffer is read inside try/catch
   and the decode is wrapped, so a stack-owned buffer belonging to a vanished
   peer cannot propagate a fault.

A `DUP=` counter now appears in the ledger, so the next test **proves** the
guard fired rather than leaving it to be inferred from the absence of a crash.

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

## Capture method: on-screen, not file-based

**File logging does not work for this crash on this hardware.** A field attempt
found no new `SKYSHIELD.TXT` and no new `CIQ_LOG.YML` entry after a reproduced
crash, only files hours older.

Two independent reasons, either of which is sufficient:

1. **A System Error kills the app before the log buffer is flushed.** Connect IQ
   writes `println` output on a clean app exit or periodic flush. A stackless
   system fault is neither, so the buffer is lost with the process.
2. **MTP has no safe-eject and caches aggressively.** Even a written file may not
   appear until the device is unmounted and re-enumerated.

So the ledger no longer depends on a file. **Every counter is written to
`Application.Storage` as it changes.** Storage commits to flash immediately and
survives the crash, and the next launch reads it back and renders it on the
splash screen.

### How to read it

1. Reproduce the crash.
2. **Relaunch the SKYSHIELD app.**
3. The splash is replaced by a red **`PREV SESSION CRASHED`** readout, held for
   **40 seconds** so it can be read or photographed:

```text
      PREV SESSION CRASHED
          session #3

            LEDGER
      P2/U0 LEAK=2 prof1/1
        c2 d1 s2 sc3/2

           DIED AT
    teardown 5: dead device
       queued for unpair
      DISCONNECT callback #1
```

4. Photograph it and paste the values back.

No USB, no MTP, no file. If the previous session exited cleanly the readout does
not appear and the normal splash shows instead.

### How crash detection works

`beginSession()` sets a session-open flag in Storage on launch; `onStop()`
clears it. A System Error never reaches `onStop()`, so a session found still
open on the next launch did not exit cleanly. The flag is read in
`SkyShieldApp.initialize()`, which runs **before** `BleAlertSource` opens the new
session, so the crashed session's final state is captured before it is
overwritten.

### Reading the ledger

```text
P<pair>/U<unpair> LEAK=<pair-unpair> prof<reg>/<callback> c<conn> d<disc> s<sub> sc<on>/<off>
```

| Field | Meaning |
|---|---|
| `LEAK` | connection slots acquired and never released — **the headline figure** |
| `prof` | profile registrations / callbacks, which have no unregister at all |
| `c` / `d` | connect / disconnect callbacks |
| `s` | subscribe requests |
| `sc` | scan on / off |

`DIED AT` is the last teardown step and the last lifecycle event recorded before
the fault.

### Caveat

This build writes to flash inside BLE callbacks. That is what makes the state
survive, but it does change timing slightly. If the crash becomes intermittent
or disappears with this build installed, that is itself a finding — it would
point at a race rather than a pure resource leak, and is worth reporting.

`println` output is still emitted, so if a log file does happen to appear it
remains usable as a secondary source.

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
