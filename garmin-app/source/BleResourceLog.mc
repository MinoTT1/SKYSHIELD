import Toybox.System;

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
// This class performs no BLE calls and changes no behaviour. It only counts and
// prints.
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
        System.println("SKYSHIELD BLERES  step: " + label);
    }

    // ---- the ledger --------------------------------------------------------

    // Prints every counter plus explicit leak figures. An acquire with no
    // matching release shows up as a climbing leak across connect cycles.
    function mark(event) {
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
            " src=" + _sourceStart + "/" + _sourceStop);
    }

    // Reads for anything that wants the figures without printing.
    function pairLeak() {
        return _pair - _unpair;
    }

    function profileRegisterCount() {
        return _profileRegister;
    }
}
