# Repeated multi-byte string splitting

Both eager and lazy candidates are rejected on the recorded control evidence.
The runtime source is restored to committed `d564eb3c3`; this branch retains
focused contract tests and reviewable evidence, including both rejected patches.

Materialized `String.split` calls one-shot substring search for every field.
For a multi-byte separator and a haystack of at least 64 bytes, the pinned
memchr 2.8.3 one-shot implementation creates a `memmem::Finder` per call.
The rejected lazy candidate begins with one-shot searches and hands off after two
observed matches, only with a remaining quota and a suffix of at least 64 bytes
that can contain the separator. Absent/single-hit inputs never enter the Finder
frame. Byte separators, input shorter than 64 bytes, oversized separators, and
caps at most two disable handoff entirely. Zero caps and empty separators still
return through their existing paths.

The private continuation receives the current exclusively held list header and
valid unconsumed offset; its caller immediately returns the result. One generic
accounting loop serves initial and cached searches, with a const flag disabling
further handoff in the continuation. The forwarding helper is always inlined;
the transient stack Finder helper is not inlined. Cached searches call original
`find` below 64 bytes, preserving the short and Rabin-Karp paths. No near-window
heuristic, extra allocation, or cross-call searcher state is added.

Doing nothing remains appropriate unless measurements establish a useful
benefit: allocation/copy work may dominate splitting, and single-hit/absent
inputs cannot amortize setup. The extra cached-helper call, code placement,
and branch costs need controls as well as repeated-match wins. In particular,
do not infer multi-byte behavior from the stdlib's one-byte space benchmark.

## Prepared coverage

The 89 current cases include 2-, 7-, and 90-byte separators; 8/64/512/4096 fields;
7- and 64-byte field widths; one-byte controls with widths from 1 through
1024; 31/32/63/64/65-byte absent inputs; 4 KiB and 64 KiB absent inputs;
leading/middle/trailing single hits; caps 0/1/2; short repeated fields;
Unicode; empty input; prefix/full empty-separator controls; and exactly two hits
followed by 4 KiB/64 KiB absent tails for each multi-byte separator. Repeated
inputs end with a separator, so the checksum includes the trailing empty piece.

`identities.json` fixes the full inventory and each input byte count,
iteration count, and total checksum. Checksums are 17 per returned part plus
the sum of returned byte lengths, accumulated across iterations. A Python
byte-length/split model produced the identities independently of Manuscript
execution. Every timed split also compares its complete list of exact pieces
against an independently constructed expected list; a wrong separator position
therefore fails even if piece counts and total bytes agree. Expected lists
are constructed outside timing. The shared runner rejects failed producers
and missing, duplicate, unknown, or changed identities on every sample.

The focused source tests are
`tests/e2e/testdata/stdlib/string-split-search.ms`. They exercise exact
field contents, leading/consecutive/trailing empties, nonoverlapping matches,
truncated caps, optional `none`, Unicode, oversized separators, and threshold
transitions. They materialize the result before iterating it.

## Reproduce

Build and preserve the baseline archive from committed `d564eb3c3` with
`cargo xtask runtime`. From the same worktree path, apply `lazy-runtime.patch`
(or `initial-runtime.patch` for the eager candidate), build and preserve the
candidate archive, then restore the original runtime source. Use an exit trap
to restore saved source on failure. The archived patches are relative to the
baseline; neither is applied in this branch. Use one pinned compiler and
identical `ms_rt_hot.ll` when compiling both generated programs:

```sh
MS_RT_LIB=/tmp/split-search-before/libms_native.a /path/to/pinned-ms build \
    bench/perf/string-split-search/main.ms --build-type Release \
    -o /tmp/split-search-before-program
MS_RT_LIB=/tmp/split-search-after/libms_native.a /path/to/pinned-ms build \
    bench/perf/string-split-search/main.ms --build-type Release \
    -o /tmp/split-search-after-program
taskset -c 0 python3 bench/perf/string-lines/compare.py \
    /tmp/split-search-before-program /tmp/split-search-after-program \
    /tmp/split-search-samples.csv --pairs 7 \
    --identity-file bench/perf/string-split-search/identities.json
MS_RT_LIB=/tmp/split-search-after/libms_native.a /path/to/pinned-ms test \
    tests/e2e/testdata/stdlib/string-split-search.ms
cargo fmt --all --check
cargo nextest run -p ms-rt -E 'test(string::tests::)'
```

Verify the actual LLVM invocation before labeling a Release build as LLVM.
Record archive, helper, compiler, source and executable hashes with revision,
machine and raw samples. Input construction, checked per-case warm-up,
process startup, compilation, and CSV output are outside each timed interval;
materialized splitting, list traversal, and release are inside it. Iterations
are bounded, and the runner alternates process order. Run timings without
concurrent compilation or tests, then run the repository's applicable checks
before proposing a merge. Keep all control rows and report regressions.

## Initial Linux comparison, 2026-10-29

Intel Xeon Platinum 8573C VM, five exposed CPUs, Linux 6.18.55,
Rust 1.99.1, static musl native runtime with frame pointers. Both runtime
archives were rebuilt from this same worktree path, first using committed
`d564eb3c3`, then restoring the saved candidate with an exit trap. The pinned
compiler was unchanged (SHA-256
`3179dc962e37f64961fc16715e7dcc758b78decffb84c2e67100acb0cb044145`).
`ms_rt_hot.ll` was byte-identical in both builds (SHA-256
`8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef`).
Actual `execve` traces confirm LLVM 23.1.1 `opt -passes=default<O3>` and
`llc -O3 -align-loops=32`; see
[initial-llvm-invocations.txt](initial-llvm-invocations.txt).
[initial-builds.json](initial-builds.json) records revision, archive, compiler, source, patch,
helper, test-source, executable, and raw-data hashes.

The shared runner and children were pinned to CPU 0 with no concurrent builds,
tests, or other timed programs. Both unrecorded process warm-ups and all seven
alternating pairs succeeded, including every-piece validation and all 83 strict
identities. [initial-samples.csv](initial-samples.csv) contains all 1,162 sample
rows. [initial-summary.csv](initial-summary.csv) preserves every median and
before/after min/max range, and [initial-paired.csv](initial-paired.csv) preserves
paired signs and speedup ranges. No controls were dropped.

The repeated-field medians improved 1.13–3.15x for 2-byte separators,
1.89–3.39x for 7-byte separators, and 3.89–8.56x for 90-byte separators.
Twenty-two of these 24 cases improved in all seven paired comparisons; the two
remaining cases were the smallest 2-byte workloads (4/7 and 6/7 faster pairs).
Examples, in nanoseconds per complete split including exact-output validation:

| Case | Before median | After median | After range | Speedup | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `d2_w7_fields8` | 212.3 | 188.0 | 174.8–249.0 | 1.129x | 4/7 |
| `d2_w7_fields64` | 3024.3 | 1100.9 | 893.7–2408.5 | 2.747x | 7/7 |
| `d2_w7_fields4096` | 210865.0 | 67279.9 | 57720.7–78110.0 | 3.134x | 7/7 |
| `d7_w7_fields8` | 413.4 | 207.2 | 181.8–232.3 | 1.995x | 7/7 |
| `d7_w7_fields64` | 3822.7 | 1153.1 | 1042.7–1640.3 | 3.315x | 7/7 |
| `d7_w7_fields4096` | 239626.2 | 70752.7 | 62623.0–161876.0 | 3.387x | 7/7 |
| `d90_w7_fields8` | 5195.6 | 1336.0 | 1061.1–1552.7 | 3.889x | 7/7 |
| `d90_w7_fields64` | 42095.3 | 5418.9 | 4884.6–7660.7 | 7.768x | 7/7 |
| `d90_w7_fields4096` | 2794722.0 | 329983.1 | 276664.9–360069.0 | 8.469x | 7/7 |

This candidate is **not accepted** on the current evidence. Several controls
showed material regression, including six absent-input cases, end single hits,
and a one-byte control. The table below lists every median regression, including
small or mixed-sign cases; `slower pairs` counts pairs where the candidate took
longer. Wide ranges and inconsistent signs limit conclusions about small
changes, but do not justify discarding these controls.

| Case | Before median ns | After median ns | Speedup | Slower pairs |
| --- | ---: | ---: | ---: | ---: |
| `d2_absent_n31` | 42.0 | 43.2 | 0.972x | 4/7 |
| `d2_absent_n64` | 63.9 | 64.2 | 0.995x | 3/7 |
| `d2_absent_n4096` | 397.2 | 584.1 | 0.680x | 5/7 |
| `d2_absent_n65536` | 9011.8 | 9979.4 | 0.903x | 4/7 |
| `d2_limit1` | 58.1 | 63.4 | 0.916x | 4/7 |
| `d7_absent_n64` | 70.4 | 75.1 | 0.937x | 5/7 |
| `d7_absent_n65` | 74.1 | 90.2 | 0.822x | 5/7 |
| `d7_absent_n4096` | 532.3 | 631.8 | 0.843x | 6/7 |
| `d7_absent_n65536` | 9330.2 | 11945.6 | 0.781x | 6/7 |
| `d7_limit1` | 69.7 | 72.1 | 0.966x | 3/7 |
| `d90_absent_n63` | 39.5 | 41.9 | 0.943x | 5/7 |
| `d90_absent_n4096` | 907.6 | 1099.8 | 0.825x | 6/7 |
| `d90_absent_n65536` | 9692.2 | 11715.2 | 0.827x | 5/7 |
| `d90_limit1` | 701.2 | 733.2 | 0.956x | 5/7 |
| `byte_w1` | 7713.5 | 7932.2 | 0.972x | 4/7 |
| `byte_w31` | 14491.2 | 15406.6 | 0.941x | 4/7 |
| `byte_w64` | 15971.7 | 16367.0 | 0.976x | 6/7 |
| `byte_w1024` | 75672.5 | 83628.3 | 0.905x | 6/7 |
| `short_fields_pad0` | 60.1 | 60.7 | 0.991x | 2/7 |
| `empty` | 20.3 | 20.7 | 0.982x | 4/7 |
| `empty_separator` | 79.6 | 82.4 | 0.966x | 5/7 |
| `d2_single_hit_at0` | 9497.0 | 10063.5 | 0.944x | 4/7 |
| `d2_single_hit_at65536` | 9201.8 | 9709.8 | 0.948x | 6/7 |
| `d7_single_hit_at0` | 9930.3 | 11464.3 | 0.866x | 5/7 |
| `d7_single_hit_at65536` | 10167.3 | 12652.0 | 0.804x | 6/7 |
| `d90_single_hit_at0` | 10855.7 | 11391.9 | 0.953x | 4/7 |
| `d90_single_hit_at65536` | 9959.3 | 10541.1 | 0.945x | 5/7 |

The initial benchmark source and identity inventory are preserved as
[initial-main.ms](initial-main.ms) and [initial-identities.json](initial-identities.json).
The initial runtime patch is preserved as
[initial-runtime.patch](initial-runtime.patch). Any follow-up needs to explain
and remeasure the control costs before recommending this change. No mechanism
for the observed regressions has yet been established; extra helper work and
native code layout remain hypotheses.

Correctness checks passed: three focused compiled source tests, 20 existing
`ms-rt` string unit tests, source checks for the fixture and benchmark,
`cargo fmt --all --check`, and `git diff --check`. No conformance-corpus or
workspace-wide check is claimed for this candidate yet.

## Lazy handoff comparison, 2026-10-29

The approved source-only follow-up began with one-shot search. It entered a
cached continuation after two observed matches only when quota remained and
a suffix of at least 64 bytes could still contain the delimiter. The accounting
helper was always inlined and the Finder continuation was not inlined. This
made absent/single-hit inputs avoid the Finder frame and gave byte/short inputs
and caps at most two a transition-free specialization. This was a causal attempt
to amortize setup; no padding, placement tuning, disassembly, or backend/ownership
inspection was used.

The same-path baseline archive remained unchanged. A separate lazy archive was
built and checked with identical pure-helper IR and the unchanged pinned compiler.
Both programs were rebuilt from the same 89-case source; six new controls cover
exactly two matches followed by an absent 4 KiB/64 KiB tail, for every multi-byte
separator. The same CPU 0 isolation, LLVM 23.1.1 Release flags, checked warm-ups,
and seven alternating pairs apply. [lazy-builds.json](lazy-builds.json) records
all source/archive/helper/compiler/program/data hashes and
[lazy-llvm-invocations.txt](lazy-llvm-invocations.txt) records normal build invocations.

Every producer and exact-piece check passed. [lazy-samples.csv](lazy-samples.csv)
contains all 1,246 sample rows; [lazy-summary.csv](lazy-summary.csv) retains all
89 medians and before/after ranges; [lazy-paired.csv](lazy-paired.csv) retains every
paired sign and ratio range. The unchanged 83-case eager evidence remains above.

Twenty-three of 24 repeated-field median comparisons improved. Representative
retained gains, in nanoseconds per complete split including validation:

| Case | Before median | After median | After range | Speedup | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `d2_w7_fields8` | 169.4 | 211.1 | 179.6–450.7 | 0.802x | 0/7 |
| `d2_w7_fields64` | 2987.5 | 1098.2 | 999.4–1733.2 | 2.720x | 7/7 |
| `d2_w7_fields4096` | 206211.2 | 70264.6 | 57651.7–77824.8 | 2.935x | 7/7 |
| `d7_w7_fields64` | 3749.1 | 1209.0 | 1123.0–1310.4 | 3.101x | 7/7 |
| `d7_w7_fields512` | 34343.3 | 8581.4 | 7546.9–13318.4 | 4.002x | 7/7 |
| `d7_w7_fields4096` | 267517.8 | 75168.7 | 57242.0–86165.2 | 3.559x | 7/7 |
| `d90_w7_fields64` | 42497.8 | 6182.4 | 5800.8–7844.6 | 6.874x | 7/7 |
| `d90_w7_fields4096` | 2649040.8 | 310364.7 | 265958.1–493542.7 | 8.535x | 7/7 |
| `d90_w64_fields4096` | 2907710.2 | 401473.5 | 368997.5–432915.3 | 7.243x | 7/7 |

The lazy candidate is also **rejected**. All six exactly-two-hit controls regressed,
three with seven slower pairs; all six one-byte controls regressed. Material absent
and single-hit costs also persisted despite those paths avoiding the Finder frame.
No cause for those latter changes has been established. The complete median
regression inventory follows; small/mixed-sign results are retained too:

| Case | Before median ns | After median ns | Speedup | Slower pairs |
| --- | ---: | ---: | ---: | ---: |
| `d2_w7_fields8` | 169.4 | 211.1 | 0.802x | 7/7 |
| `d2_absent_n31` | 40.6 | 48.7 | 0.834x | 6/7 |
| `d2_absent_n4096` | 478.3 | 565.4 | 0.846x | 4/7 |
| `d2_absent_n65536` | 8652.9 | 11087.1 | 0.780x | 7/7 |
| `d2_limit0` | 9.8 | 10.8 | 0.900x | 3/7 |
| `d7_absent_n31` | 42.5 | 46.5 | 0.912x | 4/7 |
| `d7_absent_n63` | 94.8 | 110.4 | 0.859x | 5/7 |
| `d7_absent_n65` | 78.7 | 82.7 | 0.952x | 4/7 |
| `d7_absent_n4096` | 538.2 | 638.9 | 0.842x | 6/7 |
| `d7_absent_n65536` | 9322.5 | 12049.0 | 0.774x | 6/7 |
| `d7_limit0` | 8.8 | 11.2 | 0.787x | 5/7 |
| `d90_absent_n63` | 38.8 | 39.1 | 0.993x | 5/7 |
| `d90_absent_n64` | 34.7 | 37.5 | 0.925x | 5/7 |
| `d90_absent_n65` | 35.9 | 38.3 | 0.938x | 4/7 |
| `d90_absent_n4096` | 1015.9 | 1158.0 | 0.877x | 4/7 |
| `d90_absent_n65536` | 10625.5 | 11327.8 | 0.938x | 5/7 |
| `d90_limit0` | 7.8 | 10.7 | 0.725x | 5/7 |
| `d90_limit2` | 1399.5 | 1428.0 | 0.980x | 5/7 |
| `byte_w1` | 7656.7 | 8720.7 | 0.878x | 6/7 |
| `byte_w7` | 6322.6 | 7816.8 | 0.809x | 5/7 |
| `byte_w16` | 10555.4 | 12092.7 | 0.873x | 5/7 |
| `byte_w31` | 14157.7 | 15601.6 | 0.907x | 5/7 |
| `byte_w64` | 15348.8 | 17312.9 | 0.887x | 5/7 |
| `byte_w1024` | 71228.4 | 94300.1 | 0.755x | 6/7 |
| `short_fields_pad1` | 62.3 | 67.4 | 0.924x | 5/7 |
| `short_fields_pad56` | 123.5 | 130.9 | 0.943x | 5/7 |
| `short_fields_pad57` | 103.2 | 109.6 | 0.942x | 2/7 |
| `short_fields_pad58` | 107.1 | 112.4 | 0.954x | 2/7 |
| `empty_separator` | 77.9 | 101.1 | 0.770x | 4/7 |
| `d2_single_hit_at32768` | 9541.3 | 11116.4 | 0.858x | 5/7 |
| `d2_single_hit_at65536` | 9507.7 | 10457.0 | 0.909x | 5/7 |
| `d7_single_hit_at0` | 9674.5 | 10975.2 | 0.881x | 4/7 |
| `d7_single_hit_at32768` | 9368.2 | 13270.2 | 0.706x | 6/7 |
| `d7_single_hit_at65536` | 9653.5 | 11890.1 | 0.812x | 6/7 |
| `d90_single_hit_at0` | 9871.8 | 11560.3 | 0.854x | 6/7 |
| `d90_single_hit_at32768` | 10299.6 | 11757.0 | 0.876x | 6/7 |
| `d90_single_hit_at65536` | 10066.4 | 11787.1 | 0.854x | 7/7 |
| `d2_two_hits_tail4096` | 506.3 | 813.1 | 0.623x | 7/7 |
| `d2_two_hits_tail65536` | 10449.7 | 11352.3 | 0.920x | 5/7 |
| `d7_two_hits_tail4096` | 542.6 | 817.3 | 0.664x | 7/7 |
| `d7_two_hits_tail65536` | 8949.9 | 10653.2 | 0.840x | 7/7 |
| `d90_two_hits_tail4096` | 2339.7 | 2596.7 | 0.901x | 6/7 |
| `d90_two_hits_tail65536` | 10791.6 | 13259.8 | 0.814x | 6/7 |

[lazy-runtime.patch](lazy-runtime.patch) preserves the rejected revision.
Correctness checks passed: all four focused native source tests, all 20 existing
string unit tests, both frontend source checks, Rust formatting, and whitespace
checks. These results establish no acceptable overall performance improvement;
there is no recommendation to ship either patch. No workspace-wide or corpus
pass is claimed for either rejected candidate.
