[Wiki](../index.md) › [Standard-library design](index.md)

# Path text is Manuscript; only the glob matcher stays native

Decision (Chinmay, stdlib idiom proposal, 2026-11-05): lexical path functions live in `src/stdlib/os/path.ms`, split from `os/fs.ms` with no aliases. They never touch the OS, so Rust holds nothing for them. `msstd_path_compile_glob` and `msstd_path_glob_matches` (a compiled `Glob` handle; `matches_glob` is a thin wrapper) stay native because `fs.glob`'s directory walk uses the same matcher (`src/runtime/std/path_glob.c`).

Verified: the 9.7k-case corpus recorded from the original implementation replays under `tests/lang/projects/path_oracle` (an embed project, so the data file travels with the test). Port a lexical native by moving its cases into such a replay first. The `.ms` rules cost about 1x (basename, dirname, relative) to 2x (normalize, join, parse) the Rust natives, still under 300 ns; `bench/perf/pure-utilities/` keeps the old Rust rules as the control.

Path case comparisons preserve per-scalar lowercase mapping, not whole-string contextual casing. Mapping `Σ` to `σ` before lowercasing prevents final-sigma rules from changing Windows relative components and UNC roots. `accept/path-case-mapping.ms` covers sigma, combining marks, expanding lowercase mappings, final-sigma distinction and POSIX case sensitivity beyond the recorded corpus.

Apply when: changing path semantics, adding a dialect rule, or porting another pure-text native.
Evidence: [path.ms](../../../src/stdlib/os/path.ms), [oracle test](../../../tests/lang/projects/path_oracle/conformance_test.ms), [results](../../../bench/perf/pure-utilities/results-2026-11-05-path-in-manuscript.md).
Verify: `ms test tests/lang/projects/path_oracle/conformance_test.ms` passes on Linux, macOS and Windows.

Separator runs after Unicode text made path trimming and UNC parsing quadratic after the port. Scan ASCII `/` by byte position, keep single-separator fast paths, and use `Bytes.index_of_byte` for native server/share searches. `accept/path-separator-scans.ms` preserves the boundaries; the 2026-11-10 section of the [path results](../../../bench/perf/pure-utilities/results-2026-11-05-path-in-manuscript.md) includes short ASCII/Unicode and clean UNC controls.

`net/url` followed (2026-11-25): its C was deleted after a 3,466-case corpus recorded from the C replayed identically (`projects/url_oracle`). Cost in a port of record-heavy code sits in allocations, large-record copies and stores, not byte loops: profile with callgrind plus cache simulation (`--cache-sim=yes`, compare `Dw`), fill a `var` record instead of returning it through an optional, compare literals by bytes (`"x".to_bytes()` allocates), and write `Bytes.get` as source so it inlines. Result: [url](../../../bench/perf/pure-utilities/results-2026-11-25-url-in-manuscript.md).

`html_entity` followed: a 96 KB text constant holds the 2,231 references as fixed-width lines (`.`-padded names sort first) and an integer-list constant holds each name's first 8 bytes, so a lookup is an integer binary search inside a first-letter bucket. Lesson: a module constant list of integer literals is a static view (`list.const.view`); any other constant (strings are fine, floats, booleans and computed lists are not) is rebuilt on every read, so a hot table must be integers or text.
