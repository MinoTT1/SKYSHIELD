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

**1. Round trip.** Two fixture pairs run parse → encode → decode and must match
their expected file, including the exact CBOR bytes:

- `ttskw07_raw_samples.txt` — **real vendor captures**, ground truth
- `ttskw07_edge_cases.txt` — **synthetic** degradation cases

Noise and blank lines must emit no alert at all. The two files are kept
separate so invented lines can never be mistaken for device output.

Locking the bytes means any change to key assignment, enum numbering or integer
encoding fails loudly instead of shipping a format the watch cannot read.

**2. Guardrail.** Explicit negative assertions that fail if any of the four
retired misleading mappings return (see `docs/ttskw07-format.md`):

| # | Must never happen |
|---|---|
| 1 | `confidence` reported as `0` instead of `null` |
| 2 | a failed classification escalated to `CRITICAL` |
| 3 | Autel (`T:11`/`T:12`) attributed to threat `DJI` |
| 4 | a classification guessed from the description text |
| 5 | an unrecognized `T` code failing or being guessed |
| 6 | an out-of-band frequency force-fitted to a band |
| 7 | the unreliable device clock used for timing |

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

Current status: **7 mutations, 7 caught**, each tripping explicit `#1`-`#7`
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
