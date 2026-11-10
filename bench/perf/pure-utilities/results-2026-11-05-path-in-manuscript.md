# Path rules moved from Rust natives to Manuscript (2026-11-05)

Change: the 14 lexical `msstd_path_*` natives became `stdlib/os/path.ms`; only `msstd_path_matches_glob` stays native.
Baseline: main `80fd348b`, built in a separate worktree. After: this branch. Both Release builds of the same program (`ms build --build-type Release`) on the same shared Linux x86-64 VM, no other build running, three alternating runs, 200000 iterations each, times in ns per call. This is a smoke comparison, not the controlled protocol in the README; the Rust control now lives in `rust/src/path_rules.rs`.

| operation | before (Rust native) | after (Manuscript) |
| --- | --- | --- |
| basename | 36 to 38 | 35 to 36 |
| dirname | 44 | 40 to 42 |
| extension | 35 | 67 to 71 |
| normalize | 126 to 129 | 246 to 285 |
| join | 154 to 165 | 256 to 282 |
| parse | 117 to 131 | 200 to 223 |
| relative | 574 to 665 | 583 to 701 |

Reading: no operation is above 300 ns except `relative`, which did not change. In-tree users are `os/process.ms` (`which`) and `test/golden.ms`, neither a hot loop. A 16384-byte adversarial input and a 200000-slash run stay linear (6 ms total for dirname, extension, parse and normalize of the slash run plus a 50000-segment path).

## 2026-11-06: after the data-oriented rework

Change: `normalize`, `parse` and `join` work on byte spans in one pass and skip the rebuild for an already-clean POSIX path (`stdlib/os/path.ms`). Three Release builds of the same program on the shared VM (`ms build --build-type Release`, 200000 iterations, ns per call, three alternating runs, noisy): the pre-port native build (`7c0f4d7a`), merged main (`09606701`), and this branch.

| operation | native | main (first port) | this branch |
| --- | --- | --- | --- |
| basename | 28 to 59 | 30 to 38 | 23 to 30 |
| dirname | 34 to 66 | 35 to 45 | 28 to 38 |
| extension | 28 to 42 | 59 to 61 | 46 to 68 |
| normalize | 100 to 138 | 215 to 232 | 170 to 221 |
| join | 124 to 160 | 226 to 313 | 291 to 298 |
| parse | 90 to 120 | 164 to 237 | 144 to 154 |
| relative | 543 to 731 | 415 to 611 | 355 to 364 |

`bench/perf/stdlib/pathurl_bench.ms` `path.join_normalize` (join then normalize of an already-clean result): native 258 to 270, main 363 to 378, this branch 262 to 372 (bimodal on this VM).

Reading: `basename`, `dirname` and `relative` are at or below native; `normalize`, `parse`, `join` and `extension` are still above it. The remaining cost is allocation in `get`, `slice`, `to_bytes` and `decode_utf8`; the fix is a non-allocating `String.view`/`byte_at` and a string-producing builder, which is a separate change.

## 2026-11-10: Unicode separator runs

The scalar loops introduced by the path port repeatedly traversed Unicode prefixes. A string containing `é` followed by separators is not flagged ASCII, so positive `scalar_at(end - 1)` starts at the beginning on every iteration. UNC leading/share separator loops have the same failure. The correction scans ASCII slash bytes and slices only at those UTF-8 boundaries. Single-slash trims retain `take`/`drop`; server/share searches use `Bytes.index_of_byte` rather than source loops over clean names.

Baseline affected code: main `3107528e8`. Candidate source: `c15c3d375`. The baseline compiler also contains the independent scalar-case correction, which none of these operations calls; the measured trimming/UNC code is identical to main. Both compilers use Rust 1.99.1, the same current compiler/runtime sources and Release LLVM settings, with runtime helper IR available. This is a focused regression comparison, not a refresh of the global [2026-10-28 baseline](../baseline-2026-10-28.md).

Machine: shared Linux 6.18.57 x86-64 VM, AMD EPYC 9V74, four-CPU quota, 16 GiB memory limit. Measurements below ran after the local validation jobs completed. One warmup per executable/case, then nine alternating before/after samples. The [benchmark](path-separator-scan.ms) reports monotonic time around the work loop and consumes every result's byte length. Matching checksums are required. Compilation, process startup and input construction are excluded from the wall times. The raw evidence also retains whole-process CPU cost, which includes startup/setup and is not the table's timing metric: [samples](results/path-separator-scans-2026-11-10.json).

Ordinary controls, 200,000 calls per sample, median ns/call:

| Case | Before | After |
| --- | ---: | ---: |
| `basename_plain` | 43.18 | 43.34 |
| `basename_slash` | 75.20 | 64.65 |
| `basename_unicode` | 153.19 | 119.61 |
| `unc_plain` | 254.95 | 228.83 |
| `unc_unicode` | 390.23 | 297.55 |
| `unc_clean_long` | 455.77 | 427.58 |

Runs of 32,000 separators, ten calls per sample, median microseconds/call:

| Case | Before | After |
| --- | ---: | ---: |
| `basename_many` | 59628.27 | 57.12 |
| `dirname_many` | 57054.03 | 55.13 |
| `extension_many` | 60005.82 | 61.03 |
| `unc_leading_many` | 55605.35 | 90.53 |
| `unc_share_many` | 55928.79 | 83.28 |
| `join_many` | 55075.68 | 78.20 |

The long-run workloads improve by approximately 614–1044× here. The unchanged plain-basename control differs by 0.16 ns (0.4%); do not interpret that noise as a portable regression or gain. Short trailing-slash and UNC controls also improve. No absolute latency guarantee or native Windows/macOS timing is claimed; both explicit lexical dialects run on this Linux host.

Reproduce by building the benchmark with each compiler, then running each executable with a table case name, for example `ms build bench/perf/pure-utilities/path-separator-scan.ms -o /tmp/path-scan --build-type Release`, followed by `/tmp/path-scan basename_many`. The first output word is loop nanoseconds and the second is the consumed checksum. Divide by ten for `_many` cases and by 200,000 for the ordinary controls.

Verification: the new three-test `accept/path-separator-scans.ms` fixture and the existing 9.7k-case path corpus pass Cranelift Debug/Release and LLVM Release. An independent review compared the original scalar and candidate byte rules on 100,000 seeded Unicode/malformed UNC strings, with no differences. These lexical probes do not access the filesystem or change host path interpretation.
