# Rejected JSON escape-run experiment, 2026-10-31

**Rejected; no production or active-test change.** Handling adjacent escapes in
one local loop improves the dense escaped-string writer 3.434x in the full
matrix and about 3.33x in longer trials. However, protected ASCII writing is
1.46% slower in 10/12 long paired trials; empty/tiny writing also costs 3.02%/1.41%
(9/12 each). Retain the win and costs together. No further placement variant was
attempted and no excluded backend/lifetime investigation explains these results.

## Contract and candidate

Base is main `c3a96a65dee6f0d1aa7c83c30de9b835624f3b08`. The separate float
optimization #2126 is **absent on both sides**. This experiment changes only
Writer::quoted after an escape has been found: copy the preceding plain run,
then escape consecutive nonzero entries of the existing escape table without
repeating the general search. Plain strings, UTF-8 output, escape spelling,
allocation reservation, error checks and byte budgets retain their contract.
The [unapplied zero-context patch](variants/candidate.patch) reconstructs the exact
candidate with `git apply --unidiff-zero` on the pinned base.

This is a native library component comparison, not compiled-Manuscript or generated
serializer parity. Rust uses idiomatic Serde JSON1.0.154 with float_roundtrip and
arbitrary_precision. Both producers serialize equivalent typed values, with full
float-bit validation; exact before/after bytes agree. Rust may choose equivalent
numeric spellings. Parser representations have different lexeme contracts, so all
Rust parse ratios are null and those timings are diagnostic only.

Host: Linux x86_64 AMD EPYC9V45, CPUs0–4, shared host. Rust/Cargo1.99.1, LLVM23.1.1;
release opt-level3, panic abort, repository frame-pointer flags, same host allocator.
No local build or other benchmark ran concurrently. Setup/printing are excluded;
serialization, allocation/destruction and full-output equality guards are timed.
Eight arrays cover empty/tiny, ASCII, Unicode, dense escapes, integers, common
decimals and seeded finite float patterns. Four more float arrays cover midrange,
whole floats, exact halfways and notation/extreme/subnormal boundaries.

## Complete results

The full matrix has 576 observations and the edge matrix 144, with twelve
interleaved trials and all six producer orders twice. All calibrated counts are
retained. Nanoseconds per array; before/after >1 is improvement. The Rust column is
a writer comparison for equivalent values, not an assertion of identical layouts.

| Writer case | Before ns | Candidate ns | Rust ns | Before/candidate |
| --- | ---: | ---: | ---: | ---: |
| empty | 29.36 | 29.89 | 12.50 | 0.982x |
| tiny | 42.38 | 43.32 | 18.69 | 0.978x |
| ascii | 3616.04 | 3618.92 | 3253.31 | 0.999x |
| unicode | 5101.83 | 4671.38 | 18092.28 | 1.092x |
| escapes | 62695.84 | 18256.23 | 25607.04 | 3.434x |
| integers | 7849.31 | 7782.19 | 5466.06 | 1.009x |
| decimals | 5768.56 | 5751.94 | 6793.95 | 1.003x |
| hard-floats | 49439.66 | 50071.81 | 6847.72 | 0.987x |

The [full matrix](results/2026-10-31/full/summary.json) and
[float edges](results/2026-10-31/edges/summary.json) retain all distributions and
parser controls, including unfavorable results. Small writes appeared slower, so
one prespecified [long confirmation](results/2026-10-31/long-writes/summary.json)
covered all eight writer cases with twelve balanced A/A/candidate trials at about
700ms per baseline process: 288 complete observations. A/A uses one exact binary.

| Case | Baseline A ns | Baseline B ns | Candidate ns |
| --- | ---: | ---: | ---: |
| empty | 29.45 | 29.19 | 30.21 |
| tiny | 42.96 | 42.55 | 43.36 |
| ascii | 3603.47 | 3607.88 | 3658.19 |
| unicode | 5093.54 | 5086.45 | 4748.76 |
| escapes | 61852.54 | 62373.87 | 18642.17 |
| integers | 7898.43 | 7805.19 | 7811.86 |
| decimals | 5784.49 | 5797.03 | 5787.33 |
| hard-floats | 49730.94 | 50093.03 | 49698.33 |

ASCII baseline medians differ by 0.12%, while the candidate costs 1.46%. Paired
candidate-minus-mean(A,B) has median +47.98ns and is positive in 10/12 trials.
Empty/tiny paired costs are +0.64/+0.61ns, positive in 9/12 trials each. Overlapping
individual ranges do not erase the directional costs. The Unicode gain and dense
win are real on these workloads, but do not justify the common-path regressions.
Independent skeptical review checked the source, test expectations and statistics.

## Memory, correctness and provenance

[RSS](results/2026-10-31/memory/samples.json) records six cases × six balanced trials
× three labels =108 unique fresh processes. Whole-process peaks include setup,
semantic checks and 1,000 writes, not allocation counts. Candidate median shifts
include +64KiB empty, +122KiB Unicode, +68KiB dense and unchanged integer writing;
these observations do not identify an allocation mechanism or overturn rejection.

The candidate passes all18 scoped Rust tests:12 writer,3 failure,2 oracle,1 roundtrip.
The additional archived `adjacent_escape_runs_keep_unicode_boundaries_and_exact_budgets`
test also passes: runs at start/end, Unicode between runs, plain lengths
0/1/7/15/16/17/31/32/33/127/128, exact bytes and one-byte-short budgets. Expected
escapes are explicit, independent of the implementation. The added test is
[archived](variants/adjacent-runs-test.rs.txt), not added to the active suite.
No lifetime test, full workspace suite, Windows, HTTP, Debug JSON or compiler/backend
investigation was run under campaign exclusions. Required CI remains enabled.

[Build identities](variants/build-identities.json) pin the base, before/after
library/binary hashes, lockfile and source hashes. Sources are archived in variants:
benchmark-main.rs.txt, float-edges.rs.txt, Cargo.toml.txt and Cargo.lock.txt.
The complete outputs are losslessly bundled as payloads.json.gz keyed by original
filenames, with UTF-8, byte counts and per-entry SHA256. Manifests hash the packed
and unpacked data; every entry was round-tripped against its original bytes.
Raw timing/RSS observations and exact commands remain directly readable.

## Replay and limits

Use matched worktrees at the pinned c3a96 base. Restore the four source/manifest
snapshots into bench/perf/json-library (main.rs under src, float-edges.rs under
src/bin); copy the Python drivers there as well so their recorded source paths
resolve. Build each side with the same committed standalone lockfile and
`cargo build --release --locked --manifest-path bench/perf/json-library/Cargo.toml`.
Preserve the baseline binaries before applying the candidate patch and rebuilding.
Run run.py/edges.py with before/after/rust/output/revision, focused.py with all eight
cases and operation write, then memory.py using the exact timing binary hashes.
Each retained environment/provenance contains the complete invocation and hashes.

Production was restored after the one full and one longer experiment. This does
not establish that all JSON workloads are clean, or that the same binary timings
hold after #2126 or later main changes. The retained float optimization requires
its own combined-main replay. No speedup from this rejected candidate is shipped.
