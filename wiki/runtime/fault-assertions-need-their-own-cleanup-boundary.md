[Wiki](../index.md) › [Runtime](index.md)

# Fault assertions need their own cleanup boundary

Verified: Unix `expect_fault` children inherit the caller's cleanup stack and guard targets.
Running them can delete a still-live parent's external resources or jump to an inherited
callback guard. Clear cleanup records, guards, active fault reports and equality recursion
state in the child before the assertion runs; preserve cancellation, shielding and stack limits.

Apply when: changing fault assertions, fork boundaries or cleanup contexts.
Evidence: [child isolation](../../crates/ms-rt/src/trap.rs), [production-runtime regressions](../../crates/ms-rt/tests/trap_isolation.rs), [Windows trap entry](../../crates/ms-rt/src/trap_windows.rs), [discard-boundary regression](../../crates/ms-rt/src/fault.rs) (`trap_cleanup_boundary_tracks_discarded_caller_temporaries`), [borrowed trap helper](../../crates/ms-lower/src/testing.rs), [post-optimization unwind regression](../../crates/ms-build/tests/fault_assertion.rs), [issue #920](https://github.com/manuscript-lang/manuscript/issues/920).
Verify: child faults leave parent cleanup pending, child cleanup runs LIFO, nested assertions and assertions during fault cleanup retain their own report and cleanup boundaries.
