[Wiki](../index.md) › [Testing and conformance](index.md)

# Fuzz regressions become observable tests

Verified: the corpus holds generated fuzz fixtures under `tests/conformance/fixtures/fuzz/`; the generator was removed with the Rust conformance runner (the corpus is frozen). A fuzz-found failure becomes an observable regression test before it is called resolved, with the minimized input kept in the test.


Apply when: fixing a crash found by fuzzing or adding timing-sensitive tests.
Evidence: [corpus README](../../tests/conformance/README.md).
Verify: the minimized input lives in a regression test.
