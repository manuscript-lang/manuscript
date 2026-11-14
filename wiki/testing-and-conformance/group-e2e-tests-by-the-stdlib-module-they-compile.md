[Wiki](../index.md) › [Testing and conformance](index.md)

# Group e2e tests by the standard-library module they compile

Verified: e2e runs every fixture as a Release build, and LLVM spends about 6 s compiling a large module such as `@std/data/yaml.ms` (`MS_TIMINGS=1`: MIR at 0.26 s, codegen done at 6.29 s), once per fixture. Seven yaml regression files cost about 49 s; merged into `yaml-regressions.ms` they cost 9.4 s for the same 58 tests. Add a regression test to the existing file for its module, not a new fixture, and rename clashing helpers per section when merging.

Apply when: adding an e2e fixture under `tests/conformance/fixtures/e2e/stdlib`, or when e2e is slow.
Evidence: [yaml regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms), [e2e runner](../../tools/conform.ms) (prints the slowest fixtures), [LLVM pipeline](../../crates/ms-build/src/llvm/obj.rs).
Verify: the slowest-fixtures list at the end of `ms run tools/conform.ms` shows no module compiled by many small fixtures.
