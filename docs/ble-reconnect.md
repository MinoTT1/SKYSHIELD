# BLE Reconnect Behaviour

A dropped link is **normal operation** for this product, not an edge case. The
watch goes out of range, the screen sleeps, someone walks behind a vehicle.
Recovery has to be automatic and visible.

- Bridge: `esp32-bridge/src/main.cpp`
- Watch: `garmin-app/source/BleAlertSource.mc`
- Operator state machine: `garmin-app/source/SkyShieldView.mc`

## What was broken

**The watch never reconnected.** `startScan()` was called from exactly one
place — `start()`, at app launch. The disconnect callback cleared its state,
logged, and stopped. Nothing rearmed scanning.

A single drop left the watch dark until the app was relaunched. Because the
`LINK LOST` banner rendered correctly, the failure looked like "the bridge
stopped sending" rather than "the watch stopped listening".

Two things made it worse:

- `hasEverFoundPeripheral`, `hasEverConnected` and `hasEverSubscribed` latch
  true and were never reset. `canProcessScanCallback()` refuses to act once any
  is true, so scan results would have been ignored *even if* scanning had
  resumed.
- `garmin-app/README.md` stated: *"If BLE disconnects, `BleAlertSource` enters
  `SIGNAL_LOST` and restarts scanning."* The first half was true, the second
  was not.

## Scenario 1 — MTU across a reconnect

MTU is **per connection**. It does not carry across a reconnect, and a new
connection starts at the 23-byte default until it is renegotiated — which is
exactly the fault that once truncated every CBOR alert.

The bridge resets `mtuExchangeObserved` and invalidates the connection handle
on disconnect, then on the next connect assigns the new handle and calls
`ble_gattc_exchange_mtu()` again. `currentMtu()` always reads live from the
stack for the current handle, never a cached value.

Every connection is numbered, so the log shows the renegotiation explicitly:

```text
BLE client connected (session 2, conn_handle=1)
MTU exchange requested by bridge on handle 1
MTU negotiated: 185 (usable 182) handle=1 session=2
```

If `MTU negotiated` is missing for a session, that session is running at 23 and
alerts will be truncated. Its absence is the signal.

> `MTU exchange request returned 2` is `BLE_HS_EALREADY` and is benign: the
> central got there first. What matters is that `MTU negotiated` follows.

## Scenario 2 — disconnect detection and re-advertising

Both `onDisconnect` overloads are now overridden, matching `onConnect`. Relying
on one overload risked leaving a stale handle if the stack invoked only the
other, and a stale handle would make `currentMtu()` read a dead connection.

Disconnect handling is **idempotent**, so the second overload firing does not
double-log or re-advertise.

`startAdvertising()` is now **result-checked with one retry**. It was previously
called and assumed to succeed; a silent failure there makes the bridge
permanently undiscoverable and looks identical to the watch being out of range.

```text
BLE client disconnected (session 2, handle=1, mtu_was_negotiated=yes)
BLE advertising restarted, waiting for reconnect
```

and on failure:

```text
BLE ADVERTISING RESTART FAILED, retrying
BLE ADVERTISING STILL DOWN: bridge is undiscoverable
```

## Scenario 3 — watch rescan, reconnect, resubscribe

`scheduleReconnect()` now runs on every disconnect. It drops the dead device and
characteristic, clears the lifecycle flags, **resets the `hasEver*` latches** so
scan callbacks are processed again, and arms a rescan serviced from `tick()`.

The delegate and the registered GATT profile are deliberately **not** recreated.
They belong to the app, not to the connection; reallocating them per flap would
leak.

### State recovery

Previously, after reconnecting the operator saw **nothing** until the next alert
happened to fire — potentially minutes on a quiet link.

The bridge keeps the most recent alert readable on the alert characteristic
(`setValue()` on every publish, `READ` property set). The watch now issues a
`requestRead()` immediately after resubscribing and decodes the result through
the same path as a notification.

```text
SKYSHIELD BLE: subscribe requested
SKYSHIELD BLE: state recovery read requested
SKYSHIELD BLE: state recovery read returned 48 bytes
```

A recovered alert is a real alert that may be old; freshness is handled by the
existing packet-age logic, which will show it as `STALE` once it passes the
threshold. Recovery failing is not fatal — notifications still work, the HUD
just stays blank until the next alert.

## Scenario 4 — rapid flapping

Reconnect uses **exponential backoff**, 1s doubling to a 8s ceiling, so a link
flapping every few hundred milliseconds cannot spin the radio.

The backoff **resets to 1s once a packet actually decodes**, not merely on
connect. Connecting proves very little; a decoded packet proves the whole path
works, so the next genuine drop recovers fast rather than inheriting an
escalated delay from an earlier bad patch.

Leak and wedge review:

| Risk | Status |
|---|---|
| Delegate reallocated per reconnect | Avoided — created once in `start()` |
| Profile re-registered per reconnect | Avoided — registered once |
| Double subscription | `scheduleReconnect()` clears `isSubscribed` and the characteristic before rescanning |
| Bridge stops advertising | Result-checked with retry |
| Stale conn handle on the bridge | Invalidated on disconnect, idempotently |
| Scan callbacks permanently ignored | `hasEver*` latches reset on disconnect |
| Reconnect after deliberate `stop()` | Guarded by `_enabled` |

## Scenario 5 — what the operator sees

`SkyShieldView.getOperationalState()` resolves, in order:

1. a valid alert within `LIVE_ALERT_MS` → `LIVE`
2. `hasBleExplicitDisconnect()` → **`LINK LOST`**
3. `isBleLinkAlive()` → `MONITOR`
4. bridge activity older than `LINK_LOST_MS` → `LINK LOST`
5. otherwise `MONITOR`

`explicitDisconnectSeen` is set by the real BLE disconnect callback, so
**`LINK LOST` fires on an actual drop, not merely on an app-level timeout.**
That part always worked. What did not work was step 3 ever becoming true again,
because the watch never reconnected. It now clears on the CONNECTED callback and
the HUD returns to `MONITOR`, then `LIVE` on the next decoded alert.

## Verifying on hardware

Watch the bridge serial log throughout. Watch-side lines are visible in the
Connect IQ simulator console or via `monkeydo` on device.

### Test 1 — clean reconnect, and MTU renegotiation

1. Connect and confirm `session 1` reaches `MTU negotiated: 185`.
2. Walk the watch out of range for ~30s, or close the app.
3. Bridge should log the disconnect and `BLE advertising restarted`.
4. Watch should log `reconnect armed in 1000ms` then `reconnect attempt 1`.
5. Return to range.
6. **Confirm `MTU negotiated: 185 ... session=2`.** If this line is absent, the
   new connection is at 23 and alerts will truncate.
7. Send an alert; confirm it still decodes on the watch.

### Test 2 — state recovery

1. With a connection up, send one alert so the bridge caches it.
2. Drop the link (walk out of range or toggle watch Bluetooth).
3. Reconnect **without** sending a new alert.
4. Watch should log `state recovery read returned N bytes` and the HUD should
   show the previous alert immediately, rather than staying blank.

### Test 3 — rapid flapping

1. Toggle the watch's Bluetooth off/on repeatedly, ~5 times in ~10s.
2. Expect the backoff to escalate in the watch log (1000, 2000, 4000, 8000ms).
3. Leave it connected.
4. Confirm it settles into a working link, the bridge session counter increments
   once per connection, and there is no wedged state.
5. Confirm the backoff returns to 1000ms after the next successful alert.

### Test 4 — operator view

1. With a live link, confirm `LIVE` or `MONITOR`.
2. Walk out of range.
3. Confirm the HUD shows **`LINK LOST`** within `LINK_LOST_MS` — it must not
   keep showing a stale alert as though everything is fine.
4. Return to range.
5. Confirm it returns to `MONITOR`, then `LIVE` on the next alert.

### Test 5 — bridge survives the watch disappearing entirely

1. Connect, then power the watch off completely.
2. Confirm the bridge logs the disconnect and restarts advertising.
3. Confirm the bridge keeps accepting serial-injected alerts without crashing
   (they will log `notify` skipped, which is correct with no client).
4. Power the watch back on and confirm it reconnects unaided.
