[Wiki](../index.md) › [Runtime](index.md)

# Fault assertions need their own cleanup boundary

Verified: Unix `expect_fault` children inherit the caller's cleanup stack and guard targets.
Running them can delete a still-live parent's external resources or jump to an inherited
callback guard. Clear cleanup records, guards, active fault reports and equality recursion
state in the child before the assertion runs; preserve cancellation, shielding and stack limits.

Verified: Windows trap entry saves its cleanup boundary before returning to the generated
caller, which then discards transient per-call cleanup registrations. Lower the trap's saved
base when that discard removes caller entries; otherwise newly registered operation cleanups
can lie below the stale base and never run. Ordinary guard boundaries do not move.

Verified: the trap's caller also resumes with its owned values intact. Keep trap execution in
a borrowed-operation helper that cannot inline before unwind lowering. Otherwise an inlined
operation registers drops for the caller's live values above the guard boundary; Windows
then frees them before returning to the caller. A missing marker after a fault can reflect an
invalidated caller path, rather than a skipped close. The optimized original source fixture
exercises this distinction; a synthetic cleanup-stack test alone does not.

Apply when: changing fault assertions, fork boundaries or cleanup contexts.
Evidence: [child isolation](../../crates/ms-rt/src/trap.rs), [production-runtime regressions](../../crates/ms-rt/tests/trap_isolation.rs), [Windows trap entry](../../crates/ms-rt/src/trap_windows.rs), [discard-boundary regression](../../crates/ms-rt/src/fault.rs) (`trap_cleanup_boundary_tracks_discarded_caller_temporaries`), [borrowed trap helper](../../crates/ms-lower/src/testing.rs), [post-optimization unwind regression](../../crates/ms-build/tests/fault_assertion.rs), [issue #920](https://github.com/manuscript-lang/manuscript/issues/920).
Verify: child faults leave parent cleanup pending, child cleanup runs LIFO, nested assertions
and assertions during fault cleanup retain their own report and cleanup boundaries.
Run [implicit-close-shielded.ms](../../tests/e2e/testdata/accept/implicit-close-shielded.ms) on both
Windows architectures to cover the generated caller, trap and scope-close path together.

---
Topics: [Cleanup and resources](../topics/cleanup-and-resources.md) · [Errors and results](../topics/errors-and-results.md) · [Testing](../topics/testing.md)
