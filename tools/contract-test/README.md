# Contract Test

Guards the SKYSHIELD alert contract: the parser, the wire format, and the four
TTSKW07 mapping decisions.

```sh
./run.sh                 # contract test + independent CBOR cross-check
./verify_guardrail.sh    # prove the negative assertions actually fail
./run.sh --emit-mocks    # regenerate the Monkey C mock byte vectors
```

Requires a C++11 compiler and `python3`. No PlatformIO, no Connect IQ SDK, no
package index — that is deliberate, so it keeps running in CI and on a laptop.

## Why this exists

Before `protocol_version: 3` nothing tied the documented format to the shipped
one. The JSON schema, three protocol documents and the watch's JSON parser all
described one format while the firmware transmitted a different, undocumented
one. Nobody noticed, because no test compared them.

## What it checks

**1. Round trip.** Every line of `ttskw07_raw_samples.txt` runs
parse → encode → decode and must match `expected_alerts.txt`, including the
exact CBOR bytes. The noise line and the blank line must emit no alert at all.

Locking the bytes means any change to key assignment, enum numbering or integer
encoding fails loudly instead of shipping a format the watch cannot read.

**2. Guardrail.** Explicit negative assertions that fail if any of the four
retired misleading mappings return (see `docs/TTSKW07_MAPPING.md`):

| # | Must never happen |
|---|---|
| 1 | `confidence` reported as `0` instead of `null` |
| 2 | a failed classification escalated to `CRITICAL` |
| 3 | `AUTEL_*` attributed to threat `DJI` |
| 4 | `DJI_O3` reported as `MAVIC` |

These are separate from the fixture comparison on purpose. If they were only
enforced by the golden file, regenerating the fixture against a regressed
parser would make the test pass again. The negative assertions are phrased as
"must NOT be", so they trip regardless of what the fixture says.

**3. Codec.** Version gating, enum range validation, `null` vs `0` confidence,
rejection of every truncation, refusal to encode into an undersized buffer, and
tolerance of unknown keys from a future minor revision.

## Proving the guardrail works

A passing test proves nothing by itself: an assertion that can never fail looks
identical to one that passes.

`verify_guardrail.sh` reintroduces each retired mapping into a throwaway copy
of the tree, rebuilds, and requires the contract test to **fail**. The
production tree is never modified. A mutation that does not change the file is
reported as `[HARNESS BUG]`, not a pass — otherwise a stale pattern would
silently produce a vacuous result.

Current status: **5 mutations, 5 caught**, each tripping explicit `#1`-`#4`
assertions rather than only the fixture comparison.

## Independent cross-check

`skyshield_cbor.py` is a CBOR decoder written from RFC 8949 without reference
to the C++ implementation. The C++ encoder and decoder are a matched pair, so
they can agree with each other while both being wrong about CBOR; an
independent decoder catches that class of bug.

It also re-validates SKYSHIELD semantics on top of the golden vectors, which is
the same agreement the Monkey C decoder has to reach.

## Files

| File | Role |
|---|---|
| `contract_test.cpp` | the three test layers |
| `skyshield_cbor.py` | independent RFC 8949 decoder |
| `verify_guardrail.sh` | mutation harness proving the guardrail has teeth |
| `emit_mocks.cpp` | regenerates watch mock vectors from the real encoder |
| `run.sh` | runner |
| `../../.github/workflows/contract-test.yml` | CI |

Fixtures live in `esp32-bridge/test_samples/`.
