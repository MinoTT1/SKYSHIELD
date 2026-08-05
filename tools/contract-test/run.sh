#!/usr/bin/env bash
#
# SKYSHIELD contract test runner.
#
# Builds and runs the real parser/encoder/decoder against the captured detector
# samples, then cross-checks the same bytes with an independent Python CBOR
# decoder written from RFC 8949.
#
#   ./run.sh                 run the contract test and the cross-check
#   ./run.sh --emit-mocks    regenerate the Monkey C mock byte vectors
#
# Requires only a C++11 compiler and python3. No package index, no PlatformIO,
# no Connect IQ SDK: this must stay runnable in CI and on a laptop.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"

INCLUDE_DIR="${REPO_ROOT}/esp32-bridge/include"
SAMPLES="${REPO_ROOT}/esp32-bridge/test_samples/ttskw07_raw_samples.txt"
FIXTURE="${REPO_ROOT}/esp32-bridge/test_samples/expected_alerts.txt"
EDGE_SAMPLES="${REPO_ROOT}/esp32-bridge/test_samples/ttskw07_edge_cases.txt"
EDGE_FIXTURE="${REPO_ROOT}/esp32-bridge/test_samples/expected_edge_cases.txt"

CXX="${CXX:-g++}"
CXXFLAGS="-std=c++11 -Wall -Wextra -Werror -I${INCLUDE_DIR}"

mkdir -p "${BUILD_DIR}"

if [[ "${1:-}" == "--emit-mocks" ]]; then
    "${CXX}" ${CXXFLAGS} -o "${BUILD_DIR}/emit_mocks" "${SCRIPT_DIR}/emit_mocks.cpp"
    "${BUILD_DIR}/emit_mocks"
    echo
    echo "Paste the block above into garmin-app/source/MockAlertSource.mc" >&2
    exit 0
fi

echo "==> building contract test"
"${CXX}" ${CXXFLAGS} -o "${BUILD_DIR}/contract_test" "${SCRIPT_DIR}/contract_test.cpp"

echo "==> running contract test"
"${BUILD_DIR}/contract_test" "${SAMPLES}" "${FIXTURE}" "${EDGE_SAMPLES}" "${EDGE_FIXTURE}"

echo
echo "==> independent CBOR cross-check (python, RFC 8949)"
python3 "${SCRIPT_DIR}/skyshield_cbor.py" "${FIXTURE}"
python3 "${SCRIPT_DIR}/skyshield_cbor.py" "${EDGE_FIXTURE}"

echo
echo "ALL CONTRACT CHECKS PASSED"
