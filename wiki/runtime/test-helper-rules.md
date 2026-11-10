[Wiki](../index.md) › [runtime](index.md)

# Test helper rules

Test plans, fixtures, fault assertions and helpers that must not duplicate test blocks. Each section is one lesson.

## Testing helpers do not duplicate test blocks

Decision: the user removed `describe` and `it` callback helpers because wrapping those steps in an existing `test` block duplicates grouping without creating independently selectable or reported cases. Keep assertions directly usable in ordinary test blocks; do not restore these wrappers without a new direction.


Apply when: adding BDD helpers or test suite grouping.
Evidence: the user's explicit removal request; [testing declarations](../../stdlib/test/test.ms).
Verify: standard testing exports contain assertions, fail and skip, with no callback suite wrappers.

## Test plans distinguish declarations from executions

Verified: listing and fail-fast complete a plan with unrun entries; repeat creates separate indexed executions of one declaration. Reader completion must account for skip and intentional unrun outcomes without masking an active incomplete test. `ms test` runs each test in its own process invocation so a fault fails only that test ([design contract](../../crates/DESIGN.md)).


Apply when: changing test options, event reporting, or testing helpers.
Evidence: [test runner lowering](../../crates/ms-lower/src/runner.rs), [testing lowering](../../crates/ms-lower/src/testing.rs), [helper contracts](../../stdlib/test/test.ms), [testing fixture](../../tests/e2e/testdata/stdlib/testing.ms).
Verify: list executes no bodies, fail-fast retains later not_run entries, repeated names retain indices, and fault assertions propagate cancellation and skip.

## File fixtures own a separate lifetime from each test

Decision: the user chose an ordinary local `make_fixture()` convention and a concrete return type implementing TestHooks; tests use the implicit fixture binding, while hooks use self. No additional declaration or nesting is required. Omitted hooks are no-ops elaborated only for the canonical standard interface; written hooks retain ordinary signature checking and dispatch.

Apply when: changing fixture injection, runner hook ordering, or default hooks.
Evidence: [fixture lowering](../../crates/ms-lower/src/fixture.rs), [fixture fixture](../../tests/conformance/fixtures/e2e/stdlib/testing-fixture.ms), [testing declarations](../../stdlib/test/test.ms).
Verify: no setup for `--list`, one construction across repetitions, per-file isolation, ordinary interface calls to omitted hooks, and failure/cancellation cleanup with preserved machine outcomes.

## Fault assertions need their own cleanup boundary

Verified: Unix `expect_fault` children inherit the caller's cleanup stack and guard targets.
Running them can delete a still-live parent's external resources or jump to an inherited
callback guard. Clear cleanup records, guards, active fault reports and equality recursion
state in the child before the assertion runs; preserve cancellation, shielding and stack limits.

Apply when: changing fault assertions, fork boundaries or cleanup contexts.
Evidence: [child isolation](../../crates/ms-rt/src/trap.rs), [production-runtime regressions](../../crates/ms-rt/tests/trap_isolation.rs), [Windows trap entry](../../crates/ms-rt/src/trap_windows.rs), [discard-boundary regression](../../crates/ms-rt/src/fault.rs) (`trap_cleanup_boundary_tracks_discarded_caller_temporaries`), [borrowed trap helper](../../crates/ms-lower/src/testing.rs), [post-optimization unwind regression](../../crates/ms-build/tests/fault_assertion.rs), [issue #920](https://github.com/manuscript-lang/manuscript/issues/920).
Verify: child faults leave parent cleanup pending, child cleanup runs LIFO, nested assertions and assertions during fault cleanup retain their own report and cleanup boundaries.
