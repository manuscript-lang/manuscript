[Wiki](../index.md) › [Tooling and docs](index.md)

# Profile native programs by Manuscript position

Decision: `ms profile` replaces the debugger (the debugger and DAP are dropped). It captures sampling profiles of a native program (folded stacks, pprof-compatible output, and a `perf` map file) using frame pointers plus a PC-to-source table, and `perf record` works on any `ms build` output because the compiler keeps frame pointers and emits a perf map and DWARF line tables ([design contract](../../crates/DESIGN.md)). Report positions as `file.ms:line`, never as symbols or addresses of generated code.


Apply when: changing source maps, line tables, the perf map, or profile output formats.
Evidence: [runtime profiling](../../crates/ms-rt/src/profile.rs), [profile CLI tests](../../crates/ms-cli/tests/profile.rs), [debug artifact tests](../../crates/ms-build/tests/debug_artifacts.rs).
Verify: `cargo nextest run -p ms-cli -p ms-build`; a profile of a small program attributes samples to Manuscript lines. Treat the pages under `documentation/developer-tooling/debugging/` as possibly stale until checked against `ms profile`.
