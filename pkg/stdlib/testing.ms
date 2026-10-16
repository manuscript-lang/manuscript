# Assertions for declared test blocks. Implementations are native.

# File-level test lifecycle. A local make_fixture() returns its concrete implementer.
# Missing hooks are no-ops. All supplied hooks take no arguments and return Unit.
# Example: a file declares fn make_fixture() -> ApiFixture and impl TestHooks for ApiFixture;
# its tests access the shared concrete instance as fixture, and after_all closes its server.
export interface TestHooks:
    # Runs once after the fixture factory and before the file's selected tests.
    fn before_all() -> Unit
    # Runs before each selected test execution, including repetitions.
    fn before_each() -> Unit
    # Runs after each test attempt, including before_each failure, skip, or assertion failure.
    fn after_each() -> Unit
    # Runs once after selected tests finish or stop; also runs when before_all fails.
    fn after_all() -> Unit

# Fails unless actual is true.
export fn expect_true(actual: Bool) -> Unit:

# Fails unless actual is false.
export fn expect_false(actual: Bool) -> Unit:

# Compares using ordinary Equal semantics; reports expected and actual values on failure.
export fn expect_equal[T: Equal](actual: T, expected: T) -> Unit:

# Fails when values are equal under ordinary Equal semantics.
export fn expect_not_equal[T: Equal](actual: T, expected: T) -> Unit:

# Checks absolute difference against a finite nonnegative tolerance. NaN fails; identical infinities pass.
export fn expect_close(actual: Float, expected: Float, tolerance: Float) -> Unit:

# Checks for an exact substring without Unicode normalization.
export fn expect_contains(actual: String, expected: String) -> Unit:

# Requires some and returns its original payload; fails on none.
export fn expect_some[T](actual: Optional[T]) -> T:

# Requires none; fails when a payload is present.
export fn expect_none[T](actual: Optional[T]) -> Unit:

# Requires ok and returns its original payload; reports an unexpected error.
export fn expect_ok[T, E](actual: Result[T, E]) -> T:

# Requires error and returns its original cause; fails on success.
export fn expect_error[T, E](actual: Result[T, E]) -> E:

# Calls operation once, requires a programming fault, and returns its message. Cancellation and skip propagate.
export fn expect_fault(operation: fn() -> Unit) -> String:

# Fails the current test with a programming fault containing message.
export fn fail(message: String) -> Never:

# Stops and skips the current test, unwinding lexical cleanup. A cleanup failure overrides the skip.
export fn skip(reason: String) -> Never:

# TDD spelling of `expect_true` with the same comparison and failure behavior.
export fn assert_true(actual: Bool) -> Unit:

# TDD spelling of `expect_false` with the same comparison and failure behavior.
export fn assert_false(actual: Bool) -> Unit:

# TDD spelling of `expect_equal` with the same comparison and failure behavior.
export fn assert_equal[T: Equal](actual: T, expected: T) -> Unit:

# TDD spelling of `expect_not_equal` with the same comparison and failure behavior.
export fn assert_not_equal[T: Equal](actual: T, expected: T) -> Unit:

# TDD spelling of `expect_close` with the same comparison and failure behavior.
export fn assert_close(actual: Float, expected: Float, tolerance: Float) -> Unit:

# TDD spelling of `expect_contains` with the same comparison and failure behavior.
export fn assert_contains(actual: String, expected: String) -> Unit:

# TDD spelling of `expect_some` with the same comparison and failure behavior.
export fn assert_some[T](actual: Optional[T]) -> T:

# TDD spelling of `expect_none` with the same comparison and failure behavior.
export fn assert_none[T](actual: Optional[T]) -> Unit:

# TDD spelling of `expect_ok` with the same comparison and failure behavior.
export fn assert_ok[T, E](actual: Result[T, E]) -> T:

# TDD spelling of `expect_error` with the same comparison and failure behavior.
export fn assert_error[T, E](actual: Result[T, E]) -> E:

# TDD spelling of `expect_fault`; checks a programming fault and returns its message.
export fn assert_fault(operation: fn() -> Unit) -> String:

# documentation documentation/standard-library/testing.md
# +++
# title = "Testing helpers"
# +++
#
# # Testing helpers
#
# Import assertions from `@std/testing.ms`. Assertions stop the declared test on
# failure and retain a source fault location. Equal checks honor user-defined
# equality; Optional and Result assertions return the payload for further checks.
# The `assert_*` functions provide TDD spellings of the corresponding `expect_*` checks.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import expect_equal from "@std/testing.ms"
#
# test "adding two numbers returns their sum":
#     expect_equal(1 + 2, 3)
# ```
#
# Use independent `test` blocks for independently selected and reported cases.
# `skip(reason)` unwinds lexical cleanup and marks the test skipped.
# `expect_fault` catches programming faults only, never cancellation or skip.
# A lexical cleanup failure overrides a skip.
#
# ## File fixtures
#
# Without a local make_fixture, tests run normally with no fixture initialization
# or lifecycle hooks, even if the file declares a TestHooks implementation.
#
# A file containing tests can declare an ordinary, nongeneric
# `fn make_fixture() -> T` with no arguments. T must be a concrete source data
# type explicitly implementing this module's TestHooks interface. The compiler
# checks the contract and exposes the instance as `fixture` only inside that
# file's tests, retaining T's concrete fields and operations. Importing a factory
# does not opt the importing file in. `fixture` is a reserved word.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {TestHooks, expect_equal} from "@std/testing.ms"
#
# type CounterFixture:
#     count: Int
#
# fn make_fixture() -> CounterFixture:
#     return CounterFixture(count: 0)
#
# impl TestHooks for CounterFixture:
#     fn before_each() -> Unit:
#         self.count = 1
#
#     fn after_all() -> Unit:
#         self.count = 0
#
# test "sees initialized state":
#     expect_equal(fixture.count, 1)
# ```
#
# The runner constructs one fixture on first selected use, calls before_all,
# then before_each / test / after_each for every execution, and finally
# after_all. Omitted hooks are checked no-op implementations. An entirely
# empty `impl TestHooks for Type:` is allowed. Factory results are shared across
# repetitions and shuffled executions; test order must not be relied on.
# Tests keep independent host roots and work scopes, while the fixture owner
# stays alive until file teardown. Use before_each to reset shared mutable state.
#
# Listing or selecting no tests never creates fixtures. Factory or before_all
# failure leaves the file's selected tests not_run. after_all runs if an
# instance was returned, including when before_all fails. after_each runs even
# when before_each fails or the body skips or faults. A teardown skip cannot
# hide a prior failure; teardown faults are retained with the body failure.
# File setup/teardown failures appear in fixture_errors and fail the run.
#
# Test timeouts include before_each, the body and after_each. Factory,
# before_all and file teardown each receive the configured timeout separately.
# Cleanup is shielded from initiating cancellation. SIGINT/SIGTERM stop further
# tests and run cleanup. If timed-out fixture work does not join within the
# runner's cancellation grace, the run stops and leaves further tests not_run;
# it omits fixture teardown rather than racing cleanup against live work.
# Abrupt process exit and forced termination cannot guarantee cleanup.
#
# Run `ms test test.ms --list` to discover identities, then select one with
# `--test 'test.ms::adding two numbers returns their sum'`. Use `--json` for outcomes and durations and
# `--cpu-profile cpu.pprof --heap-profile heap.pprof --trace trace.out` to
# profile the selected tests. Capture paths resolve from the invocation directory
# and must be new; repeated executions
# contribute to one process profile, including runner and cleanup overhead.
# end-documentation
