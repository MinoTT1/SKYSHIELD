import Toybox.System;

// Measures SKYSHIELD alert latency on the watch side.
//
// IMPORTANT, and the reason this class is not simply "rxMs - timestampMs":
// the CORE clock (ms since ESP32 boot) and the watch clock (ms since app
// start) have an unknown, arbitrary offset. Their raw difference is therefore
// NOT a one-way transport latency and must never be reported as one.
//
// What this does instead is track the minimum raw difference observed across
// the session. That minimum corresponds to the fastest packet seen, so it is
// the best available estimate of (clock offset + minimum transport time).
// Every subsequent packet is then reported as EXCESS latency above that
// baseline, which is a real, honest measurement of jitter and queueing delay.
//
// The absolute one-way figure is deliberately not claimed. Obtaining it would
// require clock synchronization (an echo/round-trip exchange), which is not
// part of the current protocol.
//
// detector -> CORE latency needs none of this: both endpoints are sampled from
// the same CORE clock and arrive pre-computed in detector_latency_ms.
//
// See docs/latency-measurement.md.
class LatencyMonitor {
    var _sampleCount;
    var _baselineRawDelta;
    var _lastExcessMs;
    var _worstExcessMs;
    var _lastDetectorLatencyMs;
    var _worstDetectorLatencyMs;
    var _lastSequence;
    var _droppedPackets;

    // Receive-to-render tracking. Both endpoints are watch-clock reads, so the
    // difference is a genuine single-clock duration, unlike anything involving
    // the CORE timestamp.
    var _lastRxMs;
    var _lastRxSequence;
    var _renderedSequence;
    var _lastRenderMs;
    var _worstRenderMs;

    function initialize() {
        reset();
    }

    function reset() {
        _sampleCount = 0;
        _baselineRawDelta = null;
        _lastExcessMs = null;
        _worstExcessMs = 0;
        _lastDetectorLatencyMs = null;
        _worstDetectorLatencyMs = null;
        _lastSequence = null;
        _droppedPackets = 0;
        _lastRxMs = null;
        _lastRxSequence = null;
        _renderedSequence = null;
        _lastRenderMs = null;
        _worstRenderMs = null;
    }

    // coreTimestampMs: timestamp_ms from the packet (CORE clock)
    // localRxMs:       our own receive time (watch clock)
    // detectorLatencyMs: detector->CORE latency from the packet, or null
    function recordPacket(coreTimestampMs, localRxMs, detectorLatencyMs, sequence) {
        _sampleCount += 1;

        trackSequenceGap(sequence);

        // Kept so the render callback can close segment D on the watch clock.
        _lastRxMs = localRxMs;
        _lastRxSequence = sequence;

        _lastDetectorLatencyMs = detectorLatencyMs;

        if (detectorLatencyMs != null) {
            if ((_worstDetectorLatencyMs == null) || (detectorLatencyMs > _worstDetectorLatencyMs)) {
                _worstDetectorLatencyMs = detectorLatencyMs;
            }
        }

        // Raw difference across two unsynchronized clocks. Meaningless on its
        // own; only differences between raw deltas carry information.
        var rawDelta = localRxMs - coreTimestampMs;

        if ((_baselineRawDelta == null) || (rawDelta < _baselineRawDelta)) {
            // A new minimum means either the first sample or a faster path
            // than anything seen before. Re-baseline on it.
            _baselineRawDelta = rawDelta;
            _lastExcessMs = 0;
        } else {
            _lastExcessMs = rawDelta - _baselineRawDelta;
        }

        if (_lastExcessMs > _worstExcessMs) {
            _worstExcessMs = _lastExcessMs;
        }

        logSample(coreTimestampMs, localRxMs, rawDelta, sequence);
    }

    // The bridge sequence is monotonic, so a jump means notifications were
    // dropped between CORE and the watch. That is a transport quality signal
    // worth separating from latency.
    function trackSequenceGap(sequence) {
        if (sequence == null) {
            return;
        }

        if (_lastSequence != null) {
            var expected = _lastSequence + 1;

            if (sequence > expected) {
                var missed = sequence - expected;
                _droppedPackets += missed;
                System.println("LATENCY seq gap: expected " + expected + " got " + sequence + " (missed " + missed + ")");
            }
        }

        _lastSequence = sequence;
    }

    function logSample(coreTimestampMs, localRxMs, rawDelta, sequence) {
        var detectorText = "n/a";

        if (_lastDetectorLatencyMs != null) {
            detectorText = _lastDetectorLatencyMs + "ms";
        }

        // core_tx and rx are printed raw so a capture can be re-analyzed later.
        System.println("LATENCY seq=" + sequence +
            " core_tx=" + coreTimestampMs +
            " rx=" + localRxMs +
            " raw_delta=" + rawDelta +
            " baseline=" + _baselineRawDelta +
            " transport_excess=" + _lastExcessMs + "ms" +
            " detector_to_core=" + detectorText +
            " samples=" + _sampleCount +
            " dropped=" + _droppedPackets);
    }

    // Segment D: notification received -> alert actually drawn on the HUD.
    //
    // Both endpoints come from System.getTimer(), so this is a VALID measured
    // duration, in contrast to anything spanning the CORE clock. It captures
    // the decode plus the wait for the next render tick.
    //
    // Called from the draw path, which runs several times a second, so it
    // records only the first render of each packet. A later redraw of the same
    // alert is not a new delivery and would understate nothing but pollute the
    // sample set.
    function recordRendered(sequence, shownMs) {
        if ((_lastRxMs == null) || (sequence == null)) {
            return;
        }

        // Only close the timing for the packet we actually timed on receive.
        if (_lastRxSequence != sequence) {
            return;
        }

        if ((_renderedSequence != null) && (_renderedSequence == sequence)) {
            return;
        }

        _renderedSequence = sequence;
        _lastRenderMs = shownMs - _lastRxMs;

        if (_lastRenderMs < 0) {
            // Cannot happen with a monotonic timer; refuse to report a negative
            // duration rather than printing nonsense.
            _lastRenderMs = null;
            return;
        }

        if ((_worstRenderMs == null) || (_lastRenderMs > _worstRenderMs)) {
            _worstRenderMs = _lastRenderMs;
        }

        System.println("LATENCY seq=" + sequence +
            " D_rx_to_shown=" + _lastRenderMs + "ms" +
            " worst=" + _worstRenderMs + "ms" +
            " [single watch clock, measured]");
    }

    function getRenderLatencyMs() {
        return _lastRenderMs;
    }

    function getWorstRenderLatencyMs() {
        return _worstRenderMs;
    }

    // Transport latency above the session baseline, in ms. Null until the
    // first packet. This is jitter, not absolute one-way latency.
    function getTransportExcessMs() {
        return _lastExcessMs;
    }

    function getWorstTransportExcessMs() {
        return _worstExcessMs;
    }

    // Exact detector->CORE latency from the last packet, in ms, or null when
    // the alert did not come from a detector line.
    function getDetectorLatencyMs() {
        return _lastDetectorLatencyMs;
    }

    function getWorstDetectorLatencyMs() {
        return _worstDetectorLatencyMs;
    }

    function getSampleCount() {
        return _sampleCount;
    }

    function getDroppedPacketCount() {
        return _droppedPackets;
    }

    // Compact HUD/debug string. Shows "--" rather than a fabricated number
    // when no measurement exists yet.
    function formatSummary() {
        if (_sampleCount == 0) {
            return "LAT --";
        }

        var text = "LAT +" + _lastExcessMs + "ms";

        if (_lastDetectorLatencyMs != null) {
            text += " D" + _lastDetectorLatencyMs;
        }

        return text;
    }
}
