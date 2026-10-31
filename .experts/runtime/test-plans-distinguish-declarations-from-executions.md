[Wiki](../index.md) › [Runtime](index.md)

# Test plans distinguish declarations from executions

Verified: listing and fail-fast complete a plan with unrun entries; repeat creates separate indexed executions of one declaration. Reader completion must account for skip and intentional unrun outcomes without masking an active incomplete test. `ms test` runs each test in its own process invocation so a fault fails only that test ([design contract](../../crates/DESIGN.md)).

Apply when: changing test options, event reporting, or testing helpers.
Evidence: [test runner lowering](../../crates/ms-lower/src/runner.rs), [testing lowering](../../crates/ms-lower/src/testing.rs), [helper contracts](../../stdlib/test.ms), [testing fixture](../../tests/e2e/testdata/stdlib/testing.ms).
Verify: list executes no bodies, fail-fast retains later not_run entries, repeated names retain indices, and fault assertions propagate cancellation and skip.

---
Topics: [Testing](../topics/testing.md)
