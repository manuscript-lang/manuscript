[Wiki](../index.md) › [Standard-library design](index.md)

# Path text is Manuscript; only the glob matcher stays native

Decision (Chinmay, stdlib idiom proposal, 2026-11-05): lexical path functions live in `stdlib/os/path.ms`, split from `os/fs.ms` with no aliases. They never touch the OS, so Rust holds nothing for them. `msstd_path_matches_glob` stays native because `fs.glob`'s directory walk uses the same matcher (`ms-std-path::glob`).

Verified: the 9.7k-case corpus recorded from the original implementation replays under `tests/e2e/testdata/projects/path_oracle` (an embed project, so the data file travels with the test). Port a lexical native by moving its cases into such a replay first. The `.ms` rules cost about 1x (basename, dirname, relative) to 2x (normalize, join, parse) the Rust natives, still under 300 ns; `bench/perf/pure-utilities/rust/src/path_rules.rs` keeps the old Rust rules as the control.

Apply when: changing path semantics, adding a dialect rule, or porting another pure-text native.
Evidence: [path.ms](../../stdlib/os/path.ms), [oracle test](../../tests/e2e/testdata/projects/path_oracle/conformance_test.ms), [results](../../bench/perf/pure-utilities/results-2026-11-05-path-in-manuscript.md).
Verify: `ms test tests/e2e/testdata/projects/path_oracle/conformance_test.ms` passes on Linux, macOS and Windows.
