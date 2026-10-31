[Wiki](../index.md) › [Testing and conformance](index.md)

# Fuzz regressions become observable tests

Verified: the conformance tool has generated-input fuzzing (`ms-conform fuzz-gen`, `fuzz`). A fuzz-found failure becomes an observable regression test before it is called resolved, with the minimized input kept in the test.

Apply when: fixing a crash found by fuzzing or adding timing-sensitive tests.
Evidence: [fuzz module](../../crates/ms-conform/src/fuzz.rs), [corpus README](../../tests/conformance/README.md).
Verify: the minimized input lives in a regression test.

---
Topics: [Testing](../topics/testing.md)
