import Toybox.System;
import Toybox.Application;

// Diagnostic ledger for BLE resource lifecycle.
//
// PURPOSE: "Error Processing Workarea connections" is a system-level fault with
// an empty stack, so it says nothing about which resource ran out. Two fixes
// have now been shipped on reasoning alone and both failed on hardware. This
// class exists so the NEXT hardware reproduction is conclusive rather than a
// third guess.
//
// It counts every acquire against its matching release and prints a running
// ledger at each lifecycle event. After one crash, the log shows which counter
// climbed without a matching release across connect cycles.
//
// Two things make the log readable:
//
//   * The ledger prints DELTAS as explicit "leak" figures, so an imbalance is
//     visible without mentally subtracting columns.
//   * Teardown is logged step by step. The fault kills the app instantly, so
//     THE LAST LINE PRINTED IS THE LOCATION OF THE FAULT. That is the single
//     most valuable signal here.
//
// CAPTURE METHOD: println alone is NOT sufficient on this hardware. A System
// Error kills the app before the log buffer is flushed, so a crashed session
// leaves no file. Every counter is therefore ALSO written to Application.Storage
// as it changes. Storage commits to flash immediately and survives the crash, so
// the next launch can read back exactly where the previous session died and show
// it on screen -- no file, no USB, no MTP.
//
// A session-open flag distinguishes a crash from a clean exit: it is set on
// start, cleared in onStop(), and a session found still open on the next launch
// did not exit cleanly.
//
// This class performs no BLE calls. It counts, prints and persists.
class BleResourceLog {
    var _pair;
    var _unpair;
    var _profileRegister;
    var _profileCallback;
    var _connect;
    var _disconnect;
    var _subscribeRequest;
    var _subscribeSuccess;
    var _descriptorLookup;
    var _scanOn;
    var _scanOff;
    var _sourceStart;
    var _sourceStop;
    var _readRequest;
    var _readCallback;
    var _duplicateConnect;
    var _session;
    var _lastEvent;
    var _lastStep;
    var _dirty;

    // Storage keys. Short on purpose; Connect IQ storage is small.
    static const KEY_SESSION = "ss_seq";
    static const KEY_OPEN = "ss_open";
    static const KEY_LEDGER = "ss_led";
    static const KEY_STEP = "ss_step";
    static const KEY_EVENT = "ss_evt";

    function initialize() {
        _pair = 0;
        _unpair = 0;
        _profileRegister = 0;
        _profileCallback = 0;
        _connect = 0;
        _disconnect = 0;
        _subscribeRequest = 0;
        _subscribeSuccess = 0;
        _descriptorLookup = 0;
        _scanOn = 0;
        _scanOff = 0;
        _sourceStart = 0;
        _sourceStop = 0;
        _readRequest = 0;
        _readCallback = 0;
        _duplicateConnect = 0;
        _lastEvent = "none";
        _lastStep = "none";
        _dirty = false;
        _session = 0;
    }

    // Opens a persisted session. Call once at app start, AFTER reading the
    // previous session's report.
    function beginSession() {
        var previous = Application.Storage.getValue(KEY_SESSION);

        if (previous == null) {
            previous = 0;
        }

        _session = previous + 1;

        try {
            Application.Storage.setValue(KEY_SESSION, _session);
            Application.Storage.setValue(KEY_OPEN, true);
            Application.Storage.setValue(KEY_LEDGER, "no events yet");
            Application.Storage.setValue(KEY_STEP, "none");
            Application.Storage.setValue(KEY_EVENT, "session start");
        } catch (ex) {
            System.println("SKYSHIELD BLERES  storage unavailable: " + ex);
        }

        System.println("SKYSHIELD BLERES  session #" + _session + " opened");
    }

    // Marks a clean exit. Anything that skips this -- a System Error, a
    // watchdog, a power loss -- leaves the session flagged open, which is how
    // the next launch knows it crashed.
    function endSessionCleanly() {
        try {
            Application.Storage.setValue(KEY_OPEN, false);
        } catch (ex) {
            System.println("SKYSHIELD BLERES  storage unavailable on close: " + ex);
        }
    }

    // Reads the previous session's final state. Returns null when there is
    // nothing recorded or the previous session exited cleanly.
    static function readCrashReport() {
        var open = Application.Storage.getValue(KEY_OPEN);

        if (open == null) {
            return null;   // never run before
        }

        if (!open) {
            return null;   // previous session exited cleanly
        }

        return {
            :session => Application.Storage.getValue(KEY_SESSION),
            :ledger => Application.Storage.getValue(KEY_LEDGER),
            :step => Application.Storage.getValue(KEY_STEP),
            :event => Application.Storage.getValue(KEY_EVENT)
        };
    }

    // Compact ledger string. Kept short so it fits both the watch screen and a
    // storage value.
    function ledgerText() {
        return "P" + _pair + "/U" + _unpair +
            " LEAK=" + (_pair - _unpair) +
            " prof" + _profileRegister + "/" + _profileCallback +
            " c" + _connect + " d" + _disconnect +
            " s" + _subscribeRequest + " sc" + _scanOn + "/" + _scanOff +
            " rd" + _readRequest + "/" + _readCallback +
            " DUP=" + _duplicateConnect;
    }

    // Commits the current state. Called on every event so a crash cannot
    // outrun it.
    // Marks state dirty. Deliberately does NOT write to storage.
    //
    // THE MINIMAL FIX FOR THE SUBSCRIBE-SUCCESS CRASH.
    //
    // Application.Storage.setValue() is a synchronous flash write, and mark()
    // is called from inside BLE callbacks. In the subscribe-success handler
    // this was the ONLY heavyweight operation -- everything else there is a
    // field assignment or a println -- which makes it the sole candidate for
    // that crash.
    //
    // Only this one operation is deferred. The wider deferral of BLE
    // operations attempted previously broke app startup and has been reverted;
    // nothing about init, the connect callback or discovery is touched here.
    function persist() {
        _dirty = true;
    }

    // Commits pending state. MUST be called from the timer tick, never from a
    // BLE callback. Costs up to one tick (250ms) of events on a crash, which is
    // the price of not writing flash from callback context.
    function flush() {
        if (!_dirty) {
            return;
        }

        _dirty = false;

        try {
            Application.Storage.setValue(KEY_LEDGER, ledgerText());
            Application.Storage.setValue(KEY_STEP, _lastStep);
            Application.Storage.setValue(KEY_EVENT, _lastEvent);
        } catch (ex) {
            // Never let diagnostics take the app down.
        }
    }

    // ---- acquires ----------------------------------------------------------

    // Logged IMMEDIATELY BEFORE the call, so a fault inside pairDevice() still
    // leaves evidence that it was attempted.
    function pairAttempt() {
        _pair += 1;
        mark("PAIR attempt #" + _pair);
    }

    function profileRegisterAttempt() {
        _profileRegister += 1;
        mark("PROFILE register attempt #" + _profileRegister);
    }

    function profileRegisterCallback(status) {
        _profileCallback += 1;
        mark("PROFILE register callback #" + _profileCallback + " status=" + status);
    }

    function subscribeRequested() {
        _subscribeRequest += 1;
        mark("SUBSCRIBE requested #" + _subscribeRequest);
    }

    function subscribeSucceeded() {
        _subscribeSuccess += 1;
        mark("SUBSCRIBE success #" + _subscribeSuccess);
    }

    function descriptorLookup() {
        _descriptorLookup += 1;
        mark("DESCRIPTOR lookup #" + _descriptorLookup);
    }

    function readRequested() {
        _readRequest += 1;
        mark("READ requested #" + _readRequest);
    }

    function readCallback() {
        _readCallback += 1;
        mark("READ callback #" + _readCallback);
    }

    // A second CONNECTED with no disconnect between. This is the condition that
    // caused the crash; counting it proves the guard is firing rather than
    // leaving us to infer it from the absence of a fault.
    function duplicateConnect() {
        _duplicateConnect += 1;
        mark("DUPLICATE CONNECT blocked #" + _duplicateConnect);
    }

    // ---- releases ----------------------------------------------------------

    // Logged BEFORE the unpairDevice() call. If "UNPAIR executed" never appears
    // after a disconnect, the release path is not running at all -- which is
    // itself the answer, and is the specific thing the last fix could not prove.
    function unpairAttempt() {
        _unpair += 1;
        mark("UNPAIR executed #" + _unpair);
    }

    // ---- lifecycle markers -------------------------------------------------

    function sourceStarted() {
        _sourceStart += 1;
        mark("SOURCE start #" + _sourceStart);
    }

    function sourceStopped() {
        _sourceStop += 1;
        mark("SOURCE stop #" + _sourceStop);
    }

    function connected() {
        _connect += 1;
        mark("CONNECT callback #" + _connect);
    }

    function disconnected(state) {
        _disconnect += 1;
        mark("DISCONNECT callback #" + _disconnect + " state=" + state);
    }

    function scanStarted() {
        _scanOn += 1;
        mark("SCAN on #" + _scanOn);
    }

    function scanStopped() {
        _scanOff += 1;
        mark("SCAN off #" + _scanOff);
    }

    // Step marker for the abrupt-teardown walkthrough. The fault is instant and
    // stackless, so the final step printed identifies where it died.
    function step(label) {
        _lastStep = label;
        System.println("SKYSHIELD BLERES  step: " + label);
        persist();
    }

    // ---- the ledger --------------------------------------------------------

    // Prints every counter plus explicit leak figures. An acquire with no
    // matching release shows up as a climbing leak across connect cycles.
    function mark(event) {
        _lastEvent = event;
        System.println("SKYSHIELD BLERES  " + event);
        System.println("SKYSHIELD BLERES  LEDGER t=" + System.getTimer() +
            " pair=" + _pair + " unpair=" + _unpair +
            " PAIR_LEAK=" + (_pair - _unpair) +
            " prof=" + _profileRegister + "/" + _profileCallback +
            " conn=" + _connect + " disc=" + _disconnect +
            " sub=" + _subscribeRequest + "/" + _subscribeSuccess +
            " desc=" + _descriptorLookup +
            " scan=" + _scanOn + "/" + _scanOff +
            " read=" + _readRequest + "/" + _readCallback +
            " dupconn=" + _duplicateConnect +
            " src=" + _sourceStart + "/" + _sourceStop);
        persist();
    }

    // Reads for anything that wants the figures without printing.
    function pairLeak() {
        return _pair - _unpair;
    }

    function profileRegisterCount() {
        return _profileRegister;
    }
}
