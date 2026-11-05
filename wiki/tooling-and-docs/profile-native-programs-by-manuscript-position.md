[Wiki](../index.md) › [Tooling and docs](index.md)

# Profile native programs by Manuscript position

Decision: teach investigation through a runnable workload, `ms profile`, and native source breakpoints. Explain flat versus cumulative samples and retain the actual debug-information limits beside the debugger workflow. Use file/line breakpoints instead of guessing native symbol names. LLDB/GDB syntax documentation establishes command spelling, not Manuscript-specific runtime behavior; verify the executable's symbols and line mappings and distinguish actual debugger execution from artifact inspection in validation reports. Keep environment-specific addresses, sample counts and timing out of reusable output examples.


Apply when: changing source maps, line tables, the perf map, or profile output formats.
Evidence: [runtime profiling](../../crates/ms-rt/src/profile.rs), [profile CLI tests](../../crates/ms-cli/tests/profile.rs), [debug artifact tests](../../crates/ms-build/tests/debug_artifacts.rs).
Verify: run a representative profile, inspect the generated bundle and final executable line tables, and run the native debugger where installed and permitted. Keep profile CLI and debug-artifact tests passing.
