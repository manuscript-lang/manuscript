[Wiki](../index.md) › [Testing and conformance](index.md)

# Fuzz regressions become observable tests

Verified: a fuzz-found failure becomes an observable regression test before it is called resolved, with the minimized input kept in the test. The Rust `ms-conform fuzz-gen` and `fuzz` were deleted with the Rust implementation; porting them is tracked in #6225 and #6226, and `tools/ownership-fuzz.ms` is the fuzzer that remains.

Apply when: fixing a crash found by fuzzing or adding timing-sensitive tests.
Evidence: [corpus README](../../../tests/conformance/README.md), [ownership-fuzz](../../../tools/ownership-fuzz.ms).
Verify: the minimized input lives in a regression test.
