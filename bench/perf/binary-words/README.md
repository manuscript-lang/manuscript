# Fixed-width binary words — 2026-11-12

The private UInt64 reader performs two four-byte native reads and combines their halves. Reusing the existing eight-byte reader and `unsigned_word` removes repeated native calls and conversions while retaining the exact public preflight. No native primitive, public API, packing implementation, or compiler change is proposed.

## Final same-main result

Baseline `1ad25b0a22c91fbd2cdb57b59a4cd027a355d622`; proposed source is this patch. Both applications used the same formatted fixture and independently rebuilt CLI/runtime from that revision. LLVM Release, Linux x86-64, CPU affinity 4; machine and SHA-256 identities are in [metadata](current-main-2026-11-12/metadata.json). Seven alternating baseline/candidate/C triples per case; warmup and input loading precede timing. Every timed operation checks its result and checksum. Counts target at least 100 ms on the faster Manuscript side, capped at ten million; C durations can be shorter. Entries are ns per complete repeated operation (one, sixteen, or 8192 fields), not per byte. Ratios are medians of paired candidate/baseline ratios, not ratios of aggregate medians.

UInt64 LE valid cases improve 55–61%, BE 47–49%, including one-field inputs, both unsigned halves and unaligned offsets. No changed-path regression was observed. Error controls and unchanged read/pack controls are noise controls, not claimed optimizations. Five same-binary A/A controls accompany the raw pairs; the single-run environment still limits precision for small differences.

| Case | Baseline ns | Proposed ns | C ns | Paired ratio |
| --- | ---: | ---: | ---: | ---: |
| le-low-1 | 20.36 | 8.06 | 2.53 | 0.399 |
| le-low-16 | 314.01 | 131.67 | 22.63 | 0.408 |
| le-low-8192 | 162522.73 | 64105.75 | 10958.95 | 0.395 |
| le-high-1 | 20.51 | 8.35 | 2.49 | 0.393 |
| le-high-16 | 334.53 | 129.65 | 22.51 | 0.419 |
| le-high-8192 | 162438.71 | 71903.03 | 10698.92 | 0.452 |
| le-negative | 19.78 | 19.74 | 3.64 | 0.983 |
| le-huge | 20.40 | 19.73 | 3.64 | 0.969 |
| le-short | 20.34 | 19.45 | 3.79 | 0.953 |
| be-low-1 | 22.12 | 11.34 | 2.64 | 0.523 |
| be-low-16 | 352.82 | 175.55 | 23.83 | 0.516 |
| be-low-8192 | 176147.42 | 88893.64 | 11430.31 | 0.511 |
| be-high-1 | 21.84 | 11.68 | 2.61 | 0.534 |
| be-high-16 | 340.98 | 175.56 | 22.50 | 0.520 |
| be-high-8192 | 170905.28 | 88550.81 | 11217.83 | 0.510 |
| be-negative | 21.05 | 20.13 | 3.97 | 0.981 |
| be-huge | 20.37 | 19.78 | 3.88 | 0.971 |
| be-short | 20.18 | 20.45 | 3.92 | 0.978 |
| unchanged-read-u32 | 168.18 | 166.29 | 22.24 | 0.987 |
| unchanged-pack-u32 | 106.78 | 102.95 | 40.18 | 0.977 |

A/A median B/A ratios: `be-high-1` 0.989, `be-high-8192` 0.997, `be-negative` 0.999, `unchanged-pack-u32` 0.987, `unchanged-read-u32` 1.026.

## Scope and correctness

The shared 689 independent fixtures cover all eighteen numeric types, integer extrema, both byte orders, unaligned and missing-byte reads, negative and maximum offsets, exact error kind/message, signed zero, subnormals, infinities and NaN payloads. Float checks use complete byte round trips: float32 signaling NaNs quiet as the existing API does; float64 bits remain unchanged. Both current-main executables pass these fixtures against the C control. Existing binary (5) and varint (13) tests pass Debug and LLVM Release. The existing `unsigned fixed-width codecs cover entire UInt64 range` test adds a nested view and rejects an overrun even when the backing allocation has another byte. No golden output changes are needed.

UInt64 must retain `binary: out of range`; other fixed-width reads currently report `binary: value out of range`. The source guard is unchanged. Reconstructing a negative native word through `unsigned_word` preserves the unsigned high half without overflowing Int arithmetic. Existing endian handling and view bounds remain in the native helper.

The optimized C control is a complete checked operation using memcpy/byte-swap, an anti-hoisting compiler barrier, a geometrically growing builder and full returned-output checks/free. Its inline status/error representation and word-sized appends differ from Manuscript Result/Error and byte-wise builders. C ratios compare these implementations, not isolated language/compiler overhead. [C contract and sanitizer provenance](c-control/README.md) records those limits. Release and ASan/UBSan C smoke controls pass 250 cases each.

## Coverage and rejected work

The initial [f21 discovery](discovery-f21/report.json) measured 24 read/pack cases for u32, u64, i64, f32 and f64 at 1/16/8192 fields against C. Existing binary benchmarks were narrower; byte indexing is a separate scope. There is no fixed-width streaming interface to test. Packing differences do not justify adding a new primitive or changing the runtime in this pass. Neighboring widths and float paths yielded no additional clean source-only opportunity.

Historical [f21 candidate evidence](candidate-f21/report.json) is retained separately. An initial unchanged packing control was 3.9% slower; bounded ABBA yielded 0.989 and identical-binary A/A 0.999, and the final same-main control is 0.977. It was not a reproducible regression. No performance claim relies on that unchanged path. All final claims use the current-main directory.

## Reproduction

Use the repository's pinned toolchain, build runtime and CLI normally (`cargo xtask runtime`, `cargo build --release --locked -p ms-cli`). Save separate baseline and proposed CLI binaries, then build this identical `probe.ms` with each using `ms build probe.ms --build-type Release -o baseline-probe` and `-o probe`. Build `c-control/probe` with `cc -O3 -Wall -Wextra -Werror -o c-control/probe c-control/driver.c`. Run `python3 run.py --correct-only` and repeat with `--ms ./baseline-probe --out baseline-correctness`; run `python3 focus.py` for the final matrix. `run.py` without `--correct-only` reproduces the broader discovery. The scripts generate their input files and expect CPU 4 to be available; edit the explicit affinity for another machine and record it. Raw command paths describe the original isolated checkout and are provenance, not portable path requirements. `generate.py` can regenerate the fixture; format it with `ms fmt` before using identical copies.

Selected conformance, lint and repository checks are recorded alongside final evidence. Full cross-platform CI was not run locally; exact-head CI remains a publication/merge gate. No excluded compiler, ownership or build-cache investigation was performed.

Raw per-run samples, correctness dumps and A/A files from the 2026-11-12 runs are not kept in the tree (#3713); `report.json`, the tables above and `run.py` reproduce them.
