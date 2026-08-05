#!/usr/bin/env bash
#
# Proves the contract test's negative assertions actually have teeth.
#
# A passing test proves nothing on its own: assertions that can never fail look
# identical to assertions that pass. This script reintroduces each of the four
# retired misleading mappings into a COPY of the source tree, rebuilds, and
# requires the contract test to FAIL. If a mutation slips through, the guardrail
# for that mapping is decorative and is reported as such.
#
# The production tree is never modified.
#
# Rules under guard (docs/ttskw07-format.md):
#   1. confidence 0 instead of null
#   2. escalating a failed classification to CRITICAL
#   3. attributing Autel to DJI
#   4. guessing a classification from the description text
#   5. force-fitting an out-of-band frequency
#   6. trusting the unreliable device clock for timing
#
# Usage: ./verify_guardrail.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_ROOT="$(mtemp=$(mktemp -d 2>/dev/null || mktemp -d -t skyshield-guardrail) && echo "$mtemp")"

CXX="${CXX:-g++}"
SAMPLES="${REPO_ROOT}/esp32-bridge/test_samples/ttskw07_raw_samples.txt"
FIXTURE="${REPO_ROOT}/esp32-bridge/test_samples/expected_alerts.txt"
EDGE_SAMPLES="${REPO_ROOT}/esp32-bridge/test_samples/ttskw07_edge_cases.txt"
EDGE_FIXTURE="${REPO_ROOT}/esp32-bridge/test_samples/expected_edge_cases.txt"
PARSER_REL="esp32-bridge/include/TTSKW07Parser.h"

cleanup() { rm -rf "${WORK_ROOT}"; }
trap cleanup EXIT

PASSED=0
FAILED=0

# mutate <name> <description> <perl-expression>
#
# Applies the mutation to a fresh copy of the tree and requires the contract
# test to reject it. A mutation that does not change the file is treated as a
# harness bug, not a pass: otherwise a typo'd pattern would silently produce a
# vacuous "guardrail works" result.
mutate() {
    local name="$1"
    local description="$2"
    local expression="$3"

    local work="${WORK_ROOT}/${name}"
    rm -rf "${work}"
    mkdir -p "${work}"
    cp -R "${REPO_ROOT}/esp32-bridge" "${work}/esp32-bridge"
    cp -R "${REPO_ROOT}/tools" "${work}/tools"

    local target="${work}/${PARSER_REL}"

    perl -0pi -e "${expression}" "${target}"

    if cmp -s "${REPO_ROOT}/${PARSER_REL}" "${target}"; then
        echo "  [HARNESS BUG] ${name}: mutation did not change the file"
        echo "                the pattern no longer matches; this proves nothing"
        FAILED=$((FAILED + 1))
        return
    fi

    local binary="${work}/contract_test"

    if ! "${CXX}" -std=c++11 -I"${work}/esp32-bridge/include" \
            -o "${binary}" "${work}/tools/contract-test/contract_test.cpp" 2>"${work}/build.log"; then
        echo "  [INCONCLUSIVE] ${name}: mutated tree did not compile"
        sed 's/^/                /' "${work}/build.log" | head -5
        FAILED=$((FAILED + 1))
        return
    fi

    if "${binary}" "${SAMPLES}" "${FIXTURE}" "${EDGE_SAMPLES}" "${EDGE_FIXTURE}" >"${work}/test.log" 2>&1; then
        echo "  [GUARDRAIL HOLE] ${name}: ${description}"
        echo "                   contract test PASSED with the old mapping restored"
        FAILED=$((FAILED + 1))
        return
    fi

    local caught
    caught="$(grep -c '^  FAIL' "${work}/test.log" || true)"
    echo "  [CAUGHT] ${name}: ${description}"
    echo "           contract test failed as required (${caught} assertions tripped)"
    grep '^  FAIL' "${work}/test.log" | head -3 | sed 's/^  FAIL /             - /'
    PASSED=$((PASSED + 1))
}

echo "SKYSHIELD guardrail verification"
echo "Reintroducing each banned behaviour; the contract test must reject every one."
echo

# --- #1: report confidence 0 instead of leaving it null ----------------------
mutate "confidence-zero" \
    "confidence reported as 0 instead of null" \
    's/\Qalert.hasConfidence = false;\E/alert.hasConfidence = true; alert.confidence = 0;/'

# --- #2a: escalate an unclassifiable detection to CRITICAL -------------------
mutate "escalate-on-ignorance" \
    "failed classification escalated to CRITICAL" \
    's/\Qalert.severity = detail::severityFromDistance(alert.distance, severityPolicy);\E/alert.severity = (alert.threat == THREAT_UNKNOWN) ? SEVERITY_CRITICAL : detail::severityFromDistance(alert.distance, severityPolicy);/'

# --- #2b: policy table itself emits CRITICAL ---------------------------------
mutate "policy-emits-critical" \
    "severity policy table tuned to emit CRITICAL" \
    's/\QSEVERITY_HIGH,    \/\/ NEAR\E/SEVERITY_CRITICAL, \/\/ NEAR/'

# --- #3: attribute Autel to DJI ----------------------------------------------
mutate "autel-as-dji" \
    "AUTEL T:11 and T:12 attributed to threat DJI" \
    's/\Qcase 11: case 12:           \/\/ AUTEL SkyLink\E/case 11: case 12: return THREAT_DJI; \/\//'

# --- #4: guess a classification from the description text --------------------
mutate "guess-from-text" \
    "unrecognized T code guessed from the description text" \
    's/\Qdefault:                    \/\/ T:07 Unknown\E/default: return THREAT_DJI; \/\//'

# --- #5: force-fit an out-of-band frequency to the nearest band --------------
mutate "force-fit-band" \
    "out-of-band frequency snapped to the nearest band" \
    's/\Qreturn BAND_UNKNOWN;\E/return (megahertz < 4000u) ? BAND_2_4 : BAND_5_8;/'

# --- #6: trust the device clock for timing -----------------------------------
mutate "trust-device-clock" \
    "alert timestamp taken from the unreliable device clock" \
    's/\Qalert.timestampMs = timestampMs;\E/alert.timestampMs = 0;/'

echo
echo "${PASSED} mutations caught, ${FAILED} not caught"

if [[ "${FAILED}" -gt 0 ]]; then
    echo "GUARDRAIL VERIFICATION FAILED: at least one retired mapping could return unnoticed"
    exit 1
fi

echo "GUARDRAIL VERIFIED: every retired mapping is rejected by the contract test"
