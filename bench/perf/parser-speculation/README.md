# Failed type-argument speculation — 2026-10-31

Nested indexing repeatedly retries an unsuccessful type interpretation of the
same remaining tokens. Reuse nested failures with their original cursor,
nesting-depth effects, consumed node IDs and diagnostic. Starting depth is part
of the key: nesting-limit failures are context-dependent. Root brackets only
replay; they never populate the failure stack. Numeric starts bypass the helper
because they cannot be retried as types.

Baseline: `adb3c12a71432cc1f7b4bbd243e05f239adde763` (the type-suffix fix).
Candidate source: `7bacce99517c45fcefb7efad9fb075e8d8ba1fc3`; the measured parser
fingerprint is `faff9436f85674deba31a34b3ed357cd5dee4694e6688002c28f51a4e6c952a0`.
The source commit contains the exact measured parser, tests and harness. The raw
record retains the dirty checkout's original HEAD as well as this source commit.

These are measurements of the **Rust compiler implementation**, not generated
Manuscript-versus-Rust programs. No checker, lowering, backend or runtime code is
exercised. Linux x86_64, kernel 6.18.57, glibc 2.41, AMD EPYC 9V45 VM, CPU 0;
Rust 1.99.1, opt-level 3, debug 1, panic abort, frame pointers enabled.

| Workload | Baseline µs/pass | Candidate µs/pass | Speedup |
| --- | ---: | ---: | ---: |
| Tiny plain source | 0.540 | 0.557 | 0.97x |
| 256 plain signatures | 103.254 | 104.580 | 0.99x |
| One-level indexing | 0.715 | 0.722 | 0.99x |
| Two-level indexing | 0.937 | 0.970 | 0.97x |
| Four-level indexing | 1.330 | 1.293 | 1.03x |
| Eight-level indexing | 2.625 | 2.101 | 1.25x |
| 64-level indexing | 89.373 | 14.540 | 6.15x |
| 128-level indexing | 352.529 | 28.584 | 12.33x |
| 256-level indexing | 1372.567 | 56.508 | 24.29x |
| Flat name indexing | 0.983 | 0.981 | 1.00x |
| Flat value indexing | 1.056 | 1.061 | 1.00x |
| Nested index followed by 256 flat indexes | 96.375 | 95.068 | 1.01x |
| Standard-library corpus, 45 files | 4822.188 | 4823.644 | 1.00x |

The tiny source and depth-two controls have consistent costs of about 17 ns
(3.1%) and 33 ns (3.5%), respectively; these are tradeoffs, not claims of noise.
Generic application at depth 16 costs another 217 ns (2.4%). Whole-file ordinary
and corpus controls remain approximately unchanged. The independent reviewer
recommended keeping the scoped quadratic fix with these costs disclosed.

## Protocol and validation

The [shared harness](../parser-suffix/bench.rs) and
[runner](../parser-suffix/run.py) use ten balanced AB/BA fresh-process pairs per
case, shuffled with seed 1729: 420 samples across 21 groups. Each process warms
three passes and times at least 100 ms in batches of 16. Setup and validation are
outside the timer; parsing, source retention and destruction are inside it.
Every result is black-boxed and its node count consumed and checked.

Before timing, exact successful trees/dumps, IDs, positions and source match.
Another 220 successful/error outcomes cover malformed types and depth
990/999/1000/1001 with LF/CRLF; six partial-parser recovery results match exactly.
Errors include their exact positions, messages and repairs. There is no timing
threshold in CI. Raw distributions, input/binary/source hashes, toolchain and
parity digests are in `results-2026-10-31-initial.json`.

An additional 1,000 deterministic generated expressions (seed 1729; 364 accepted,
636 rejected) have identical full outcomes, including mixed brackets, calls,
operators, malformed types, CRLF and truncated input. Reproduce with
`python3 bench/perf/parser-speculation/parity.py BASELINE CANDIDATE NEW_OUTPUT`.

The first HashMap design was rejected after shallow-input screening. Two later
wrappers still added common-path cost; the final path avoids work for numeric
starts and makes root replay-only behavior explicit. All three complete earlier
balanced experiments are retained in `history-results.json.gz`, including a
qualification that full raw records from the initial HashMap screen were not
retained. Do not cherry-pick those experiments as accepted gains.

Six balanced peak-RSS pairs use the repository's existing
[`rss.c`](../representative/rss.c) fork/exec helper. Medians were about 1.50 MiB
for shallow indexing in both builds; deep 256-level indexing rose from 2172 to
2294 KiB, and corpus RSS was approximately unchanged. The additional failure
stack therefore has a measured small memory cost. Peak RSS includes untimed
setup and is not allocation accounting; raw readings are in
`rss-2026-10-31.json`. Allocation counts were not instrumented.

## Reproduce

Build baseline and candidate release syntax libraries and save a benchmark
binary for each, using the commands in the
[suffix protocol](../parser-suffix/README.md#reproduce). Compile the same current
`bench.rs` against both libraries, because the baseline predates outcome and
recovery modes. Then use a fresh output directory:

```sh
python3 bench/perf/parser-suffix/run.py \
  /tmp/parser-baseline /tmp/parser-candidate /tmp/speculation-results \
  --baseline-revision adb3c12a71432cc1f7b4bbd243e05f239adde763 \
  --suite speculation
```

Run without concurrent builds or benchmarks. The runner pins itself and its
children to the first available Linux CPU; VM host isolation is not claimed.
Historical files are never overwritten.

## Remaining limits

This does not make every parser path linear. Successfully ambiguous nested
generic applications retain both interpretations: depths 16/32/64 produced
208/664/2344 syntax nodes from 130/226/418 source bytes. Changing that growing
representation reaches consumers beyond this parser-only lane, including
excluded compiler stages, so no representation change was attempted here.

These measurements cover the initial combined local candidate. Normal required
CI, full combined-main benchmark controls and fresh discovery after merging are
still required; blocked or untested paths are not clean.

## Matched merged-main replay — 2026-10-31

After the suffix fix merged, baseline `649ddeb9a2fb91eb36d1eb074842eaaa4ee370fc`
was rebuilt and compared against candidate `241a49115` containing that same main
plus this cache. This includes merged formatter, recovery and Unicode-span
correctness fixes. All syntax tests, clippy, formatting and repository checks
passed after the merge; exact outcome/recovery parity and all 420 timed samples
passed again. Raw evidence is `results-2026-10-31-current-main.json`.

| Control | Baseline µs/pass | Candidate µs/pass | Speedup |
| --- | ---: | ---: | ---: |
| Tiny source | 0.537 | 0.556 | 0.97x |
| 256 plain signatures | 103.793 | 105.122 | 0.99x |
| 256 generic optional signatures | 203.824 | 203.187 | 1.00x |
| One-level indexing | 0.703 | 0.720 | 0.98x |
| Two-level indexing | 0.931 | 0.925 | 1.01x |
| 64-level indexing | 90.551 | 14.496 | 6.25x |
| 128-level indexing | 348.776 | 28.316 | 12.32x |
| 256-level indexing | 1375.625 | 56.371 | 24.40x |
| Mixed nested and flat indexing | 95.881 | 92.790 | 1.03x |
| Standard-library corpus | 4869.836 | 4826.270 | 1.01x |

The tiny-source fixed cost remains visible. A preliminary comparison against
the older pre-merge baseline had shown a roughly 4% generic-signature cost;
matching the merged-main revisions removes that confound and shows this
signature control unchanged. The preliminary measurements remain in the task
workspace; they are not used as causal acceptance evidence.

Repeat after this cache itself merges, and retain both historical runs.
