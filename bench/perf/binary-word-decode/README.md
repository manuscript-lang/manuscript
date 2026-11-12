# Decode full-width binary words directly — 2026-11-12

## Scope and result

The existing runtime `msrt_bytes_read_word` copies a dynamic-width slice into a zeroed eight-byte array and reverses the selected range for big endian. After its unchanged checked slice lookup, the candidate handles width eight with `i64::from_le_bytes` or `from_be_bytes`. Other widths retain their original fallback. No new native API, compiler, ownership or backend change is involved.

Baseline: `cd94c6423b6000a881a7772de0ff8739f6a59770` plus the UInt64 source improvement from draft #3682 (`6ee7b7bc3a86e7c0cf3dbbe25daaaef12daaa4e7`). Candidate: that same baseline plus [runtime.patch](runtime.patch). Both actual public-API fixtures were built with the same current-main compiler and LLVM Release settings; [provenance](runtime-provenance.json) records executable/source identities. This PR is stacked on #3682; the parent branch remains unchanged. Merging current main into this branch supplies the measured baseline, not additional authored fixes.

Across one, sixteen and 8192 UInt64 fields, the additional runtime change reduces paired median time by **16–24% LE** and **39–43% BE**. Both low/high unsigned halves and unaligned reads are covered. Signed64 and float64 callers also improve. Bounds/error paths remain equivalent. No meaningful persistent regression was observed in neighboring widths or unchanged packing. This does not prove zero branch overhead or performance on other hosts.

The experiment isolates a source-level runtime decoding contribution to the residual C gap. It does not identify compiler overhead. The proposed UInt64 operations still take 2.67–4.83× C time in this same-main matrix. C has different inline status/Result representation and boundary costs. The optimized C implementation uses checked bounds, memcpy/byteswap, complete value/output checks, and a per-operation memory barrier preventing repeated-read hoisting; no checks are disabled. Its contract and sanitizer evidence are retained in [the parent suite](../binary-words/c-control/README.md).

## Protocol and raw measurements

CPU 4, AMD EPYC 9V74, Linux x86-64. Seven alternating baseline/candidate/C triples per case, with input setup excluded, warmups, checked full results and consumed checksums. Each variant independently calibrates its iteration count to at least 120 ms, targeting 150 ms. Different counts are normalized to ns per complete operation. Ratios are medians of paired normalized ratios. Timing drift can produce shorter individual runs; none are removed. Page-fault observations include process startup and do not establish per-operation allocations. Instruction-count tools were not available on PATH, so no instruction-count claim is made.

| Case | Baseline ns | Proposed ns | C ns | Paired ratio |
| --- | ---: | ---: | ---: | ---: |
| le-low-1 | 8.52 | 7.60 | 2.64 | 0.838 |
| le-low-16 | 138.69 | 106.71 | 22.07 | 0.765 |
| le-low-8192 | 68323.51 | 55111.42 | 11478.14 | 0.786 |
| le-high-1 | 8.34 | 7.23 | 2.52 | 0.840 |
| le-high-16 | 133.20 | 104.93 | 23.35 | 0.784 |
| le-high-8192 | 70389.03 | 54534.18 | 11506.61 | 0.781 |
| le-negative | 19.46 | 19.93 | 3.58 | 0.997 |
| le-huge | 19.41 | 19.41 | 3.58 | 1.014 |
| le-short | 19.34 | 19.42 | 3.77 | 1.011 |
| be-low-1 | 11.79 | 7.06 | 2.61 | 0.594 |
| be-low-16 | 170.46 | 105.89 | 23.04 | 0.608 |
| be-low-8192 | 91432.70 | 53207.66 | 11425.01 | 0.594 |
| be-high-1 | 12.11 | 7.08 | 2.65 | 0.605 |
| be-high-16 | 181.03 | 105.93 | 23.08 | 0.565 |
| be-high-8192 | 90333.99 | 55649.74 | 12161.91 | 0.610 |
| be-negative | 20.95 | 20.63 | 3.91 | 0.992 |
| be-huge | 20.23 | 20.28 | 4.03 | 1.003 |
| be-short | 21.01 | 20.54 | 3.97 | 1.011 |
| neighbor-u8 | 163.87 | 159.54 | 20.91 | 0.995 |
| neighbor-u16le | 163.17 | 168.22 | 24.44 | 1.027 |
| neighbor-u16be | 170.05 | 169.33 | 25.99 | 1.011 |
| neighbor-u32be | 183.86 | 180.26 | 23.20 | 1.000 |
| neighbor-i64le | 126.01 | 102.96 | 22.54 | 0.816 |
| neighbor-i64be | 170.79 | 94.76 | 24.55 | 0.555 |
| neighbor-f64le | 144.02 | 112.84 | 27.18 | 0.775 |
| neighbor-f64be | 242.24 | 109.02 | 27.13 | 0.465 |
| unchanged-read-u32 | 174.28 | 169.57 | 23.32 | 0.982 |
| unchanged-pack-u32 | 107.67 | 107.99 | 43.17 | 1.041 |

Actual minimum sample durations (ms): baseline 126.954, candidate 130.235, c 91.344. Five same-binary A/A medians: `be-high-1` 0.979, `be-high-8192` 1.045, `be-negative` 1.020, `unchanged-pack-u32` 0.985, `unchanged-read-u32` 1.001. Raw [samples](current-main/samples.json), [case counts](current-main/cases.json) and [A/A](current-main/aa.json) are retained.

Two initial control medians needed investigation: UInt16 LE +2.66% and unchanged packing +4.06%. One bounded, seven-pair ABBA plus identical-binary A/A check gave UInt16 LE 1.0065 / 0.9930 and packing 0.9987 / 1.0145. Thus the original meaningful slowdowns did not persist. All [112 control samples](control-samples.json) and [paired ratios](control-report.json) remain available; no further variants or comparisons were used to select favorable outcomes.

## Saved #3682 comparison

Before building anything, exact saved #3682 probe `9416e15ada1ec51cdaa23977a898bc21e5f01dc2b5919662b2fafc2a8139dd60`, its pre-#3682 baseline and C identities were verified against parent evidence. The independently calibrated [saved matrix](saved-3682/report.json) confirms a 3.37–8.10× proposed/C gap on valid reads; short C durations did not explain it. These older binaries come from main `1ad25b0a22c91fbd2cdb57b59a4cd027a355d622`; do not confuse them with the runtime experiment. Shortest saved sample was C 99.992 ms after calibration, baseline 101.035 ms and proposed 118.685 ms. Nine deliberate incorrect expected-value/error controls all failed as intended.

## Correctness and validation

Both fresh baseline and candidate pass 689 independent fixtures against C: eighteen integer/float types, full UInt64 range, unaligned offsets, missing bytes, negative/extreme offsets, exact error kind/message and floating-point byte round trips. Signaling Float32 NaNs retain existing quieting behavior; Float64 payloads and signed-zero bits are preserved. Binary (5) and varint (13) tests pass Debug and LLVM Release. The inherited nested-view test rejects a read past a view despite trailing backing storage.

The new native test `read_word_preserves_bits_endian_and_error_output` checks widths 0 through 8 (including fallback widths), unaligned views, endian flags 0/1/2, mathematical bit assembly and untouched output on range failure. Width-eight conversion happens only after the checked lookup; it preserves arbitrary high bits and never dereferences unaligned typed pointers. Public UInt64's custom preflight/error is untouched.

Independent review verified the algorithm, result identities, all paired results and the bounded controls. Native Rust tests passed 220 unit tests and 12 integration tests; two existing doctests remain ignored. Formatting and workspace/all-targets Clippy passed. Initial Clippy invocations lacked the new worktree’s runtime archives; pointing `MS_NATIVE_LIB` and `MS_NATIVE_MUSL_LIB` at the already-built candidate archives resolved setup without code changes. Repository checks and selected binary/varint conformance passed; conformance lint reported 5388 fixtures and zero problems. Logs are recorded alongside this suite. `cargo-nextest` is absent from the existing toolchain; `cargo test -p ms-rt` provides local runtime coverage. Full cross-platform CI was not run locally. Exact-head CI remains required before merge.

## Reproduction

Use the repository's pinned toolchain. Build runtime and CLI normally for each source variant: `cargo xtask runtime` and `cargo build --release --locked -p ms-cli`. Save baseline as `current-baseline-ms` and candidate as `runtime-ms`; build the identical `probe.ms` with each using `--build-type Release` to `current-baseline-probe` and `runtime-probe`. Build `c-control/probe` using `cc -O3 -Wall -Wextra -Werror -o c-control/probe c-control/driver.c`. Run `run.py --correct-only --ms ./current-baseline-probe --out baseline-correctness` and repeat for `runtime-probe`. Run `runtime-focus.py`, then `controls.py`. Scripts generate inputs and require CPU 4; record an adjusted affinity on other machines.

`focus.py` reproduces the saved #3682 comparison using `baseline-probe` and `probe`, whose historical identities are in `provenance.json`. Raw absolute paths record original provenance, not portable path requirements. No production branch from an earlier held task was modified.
