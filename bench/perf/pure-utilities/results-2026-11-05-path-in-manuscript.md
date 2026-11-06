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
