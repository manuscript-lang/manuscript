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
