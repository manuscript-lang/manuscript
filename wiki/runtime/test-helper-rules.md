[Wiki](../index.md) › [runtime](index.md)

# Test helper rules

Test plans, fixtures, fault assertions and helpers that must not duplicate test blocks. Each section is one lesson.

## Testing helpers do not duplicate test blocks

Decision: the user removed `describe` and `it` callback helpers because wrapping those steps in an existing `test` block duplicates grouping without creating independently selectable or reported cases. Keep assertions directly usable in ordinary test blocks; do not restore these wrappers without a new direction.


Apply when: adding BDD helpers or test suite grouping.
Evidence: the user's explicit removal request; [testing declarations](../../stdlib/test/test.ms).
Verify: standard testing exports contain assertions, fail and skip, with no callback suite wrappers.

## Test plans distinguish declarations from executions

Verified: listing and fail-fast complete a plan with unrun entries; repeat creates separate indexed executions of one declaration. Reader completion must account for skip and intentional unrun outcomes without masking an active incomplete test. `ms test` runs every test file at once in one process, each file in its own promise ([design contract](../../crates/DESIGN.md)).


Apply when: changing test options, event reporting, or testing helpers.
Evidence: [test runner lowering](../../crates/ms-lower/src/runner.rs), [testing lowering](../../crates/ms-lower/src/testing.rs), [helper contracts](../../stdlib/test/test.ms), [testing fixture](../../tests/conformance/fixtures/e2e/stdlib/testing.ms).
Verify: list executes no bodies, fail-fast retains later not_run entries, repeated names retain indices, and fault assertions propagate cancellation and skip.

## File fixtures own a separate lifetime from each test

Decision: the user chose an ordinary local `make_fixture()` convention and a concrete return type implementing TestHooks; tests use the implicit fixture binding, while hooks use self. No additional declaration or nesting is required. Omitted hooks are no-ops elaborated only for the canonical standard interface; written hooks retain ordinary signature checking and dispatch.

Apply when: changing fixture injection, runner hook ordering, or default hooks.
Evidence: [fixture lowering](../../crates/ms-lower/src/fixture.rs), [fixture fixture](../../tests/conformance/fixtures/e2e/stdlib/testing-fixture.ms), [testing declarations](../../stdlib/test/test.ms).
Verify: no setup for `--list`, one construction per file and repetition, per-file isolation, ordinary interface calls to omitted hooks, and failure/cancellation cleanup with preserved machine outcomes.

## Fault assertions need their own cleanup boundary

`expect_fault` and `catch_fault` run the operation as a `Placement.Here` promise and read the fault report from `wait()` (error kind `EIO`, `details["report"]`), the same on every platform; the fork and Windows in-process trap are deleted (`trap.rs`, `trap_windows.rs`, `isolate_trap_child`, `live_forget_since`). A fault inside a promise exercises the real unwinder, so a leak or double free that the fork hid now fails the leak sweep: a faulting comparator in a generated sort freed the original list's elements (shadow copies and sort scratch own nothing, `ExternRole::RawSlots`, `Func::raw_scratch`; fixture `sort-driftsort-shapes.ms`). A test that needs the process to exit on a fault spawns a new process instead: Rust tests re-run themselves (`assert_fault` in `crates/ms-native/tests/std_natives.rs` re-execs the test binary and checks exit 67 and the report), and fixtures `fault-exits-process.ms` and `fault-exit-runs-open-scope-closes.ms` check the exit status and that open scopes close first.

Apply when: changing fault assertions or cleanup contexts.
Evidence: [fault assertion helpers](../../stdlib/test/test.ms), [process exit on fault](../../crates/ms-native/tests/std_natives.rs), [issue #920](https://github.com/manuscript-lang/manuscript/issues/920).
Verify: a faulting operation runs its cleanups LIFO and leaves the caller's pending; nested assertions retain their own reports.

## Tests run as promises; a file is the unit

Decision (Chinmay, 2026-11-14): `ms test` compiles one binary and runs every test file at once in a `Placement.Spread` promise; a file's tests run in order on one shared fixture. A fault stops the rest of its file; `skip(reason)?` is an `ESKIP` error so it ends only its test; a test that never waits is stopped by killing the process (cancellation is cooperative), and other files' unfinished tests rerun in a new process. Do not reintroduce a process per test or a second runner lane. A promise made in a loop reads loop variables in place (#3845): the harness uses a fork-join tree. Generated code that recurses without a stack-depth check overflows a promise task's 512 KB slot where the main task's 256 MB stack survived (#3851, #3857).

Apply when: changing `ms test`, the harness, fixtures, timeouts or output capture.
Evidence: [proposal](../../proposals/promise-test-runner.md), [harness](../../stdlib/test/runner.ms), [host](../../crates/ms-cli/src/engine/testing.rs).
Verify: the conformance test phase passes; `ms test` on a spinning test names it as timed out and finishes the other files.
