+++
title = "Testing helpers"
+++

# Testing helpers

Import assertions from `@std/testing.ms`. Assertions return a `Result` whose error
describes the failed expectation; apply `try` so the declared test stops and fails
with that message. A test block completing normally, or returning `unit`, passes;
it behaves as if it returns `Result[Unit, Error]`, so `try` and `return error(...)` fail it. Equal checks honor user-defined
equality; Optional and Result assertions return the payload for further checks.
The `assert_*` functions provide TDD spellings of the corresponding `expect_*` checks.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/testing.ms"

test "adding two numbers returns their sum":
    try expect_equal(1 + 2, 3)
```

Use independent `test` blocks for independently selected and reported cases.
`skip(reason)` unwinds lexical cleanup and marks the test skipped.
`expect_fault` catches programming faults only, never cancellation or skip.
A lexical cleanup failure overrides a skip.

## File fixtures

Without a local make_fixture, tests run normally with no fixture initialization
or lifecycle hooks, even if the file declares a TestHooks implementation.

A file containing tests can declare an ordinary, nongeneric
`fn make_fixture() -> T` with no arguments. T must be a concrete source data
type explicitly implementing this module's TestHooks interface. The compiler
checks the contract and exposes the instance as `fixture` only inside that
file's tests, retaining T's concrete fields and operations. Importing a factory
does not opt the importing file in. `fixture` is a reserved word.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {TestHooks, expect_equal} from "@std/testing.ms"

type CounterFixture:
    count: Int

fn make_fixture() -> CounterFixture:
    return CounterFixture(count: 0)

impl TestHooks for CounterFixture:
    fn before_each() -> Unit:
        self.count = 1

    fn after_all() -> Unit:
        self.count = 0

test "sees initialized state":
    try expect_equal(fixture.count, 1)
```

The runner constructs one fixture on first selected use, calls before_all,
then before_each / test / after_each for every execution, and finally
after_all. Omitted hooks are checked no-op implementations. An entirely
empty `impl TestHooks for Type:` is allowed. Factory results are shared across
repetitions and shuffled executions; test order must not be relied on.
Tests keep independent host roots and work scopes, while the fixture owner
stays alive until file teardown. Use before_each to reset shared mutable state.

Listing or selecting no tests never creates fixtures. Factory or before_all
failure leaves the file's selected tests not_run. after_all runs if an
instance was returned, including when before_all fails. after_each runs even
when before_each fails or the body skips or faults. A teardown skip cannot
hide a prior failure; teardown faults are retained with the body failure.
File setup/teardown failures appear in fixture_errors and fail the run.

Test timeouts include before_each, the body and after_each. Factory,
before_all and file teardown each receive the configured timeout separately.
Cleanup is shielded from initiating cancellation. SIGINT/SIGTERM stop further
tests and run cleanup. If timed-out fixture work does not join within the
runner's cancellation grace, the run stops and leaves further tests not_run;
it omits fixture teardown rather than racing cleanup against live work.
Abrupt process exit and forced termination cannot guarantee cleanup.

Run `ms test test.ms --list` to discover identities, then select one with
`--test 'test.ms::adding two numbers returns their sum'`. Use `--json` for outcomes and durations and
`--cpu-profile cpu.pprof --heap-profile heap.pprof --trace trace.out` to
profile the selected tests. Capture paths resolve from the invocation directory
and must be new; repeated executions
contribute to one process profile, including runner and cleanup overhead.
