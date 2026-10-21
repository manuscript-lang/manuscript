# Assertions for declared test blocks. Each returns a Result whose error describes the failed expectation;
# apply `try` so a test block returns that error and fails. Implementations are native.
# File-level test lifecycle. A local make_fixture() returns its concrete implementer.
# Missing hooks are no-ops. All supplied hooks take no arguments and return Unit.
# Example: a file declares fn make_fixture() ApiFixture and impl TestHooks for ApiFixture;
# its tests access the shared concrete instance as fixture, and after_all closes its server.
export interface TestHooks:
    # Runs once after the fixture factory and before the file's selected tests.
    var fn before_all() Unit
    # Runs before each selected test execution, including repetitions.
    var fn before_each() Unit
    # Runs after each test attempt, including before_each failure, skip, or assertion failure.
    var fn after_each() Unit
    # Runs once after selected tests finish or stop; also runs when before_all fails.
    var fn after_all() Unit

# Fails unless actual is true.
export fn expect_true(actual: Bool) Result[Unit, Error]:

# Fails unless actual is false.
export fn expect_false(actual: Bool) Result[Unit, Error]:

# Compares using ordinary Equal semantics; reports expected and actual values on failure.
export fn expect_equal[T: Equal](actual: T, expected: T) Result[Unit, Error]:

# Fails when values are equal under ordinary Equal semantics.
export fn expect_not_equal[T: Equal](actual: T, expected: T) Result[Unit, Error]:

# Checks absolute difference against a finite nonnegative tolerance. NaN fails; identical infinities pass.
export fn expect_close(
    actual: Float,
    expected: Float,
    tolerance: Float
) Result[Unit, Error]:

# Checks for an exact substring without Unicode normalization.
export fn expect_contains(actual: String, expected: String) Result[Unit, Error]:

# Requires some and returns its original payload; fails on none.
export fn expect_some[T](actual: Optional[T]) Result[T, Error]:

# Requires none; fails when a payload is present.
export fn expect_none[T](actual: Optional[T]) Result[Unit, Error]:

# Requires ok and returns its original payload; reports an unexpected error.
export fn expect_ok[T, E: Error](actual: Result[T, E]) Result[T, Error]:

# Requires error and returns its original cause; fails on success.
export fn expect_error[T, E: Error](actual: Result[T, E]) Result[E, Error]:

# Calls operation once, requires a programming fault, and returns its message. Cancellation and skip propagate.
export fn expect_fault(operation: fn() Unit) Result[String, Error]:

# Returns an error with message; `try fail(message)` fails the current test.
export fn fail(message: String) Result[Unit, Error]:

# Stops and skips the current test, unwinding lexical cleanup. A cleanup failure overrides the skip.
export fn skip(reason: String) Never:

# TDD spelling of `expect_true` with the same comparison and failure behavior.
export fn assert_true(actual: Bool) Result[Unit, Error]:

# TDD spelling of `expect_false` with the same comparison and failure behavior.
export fn assert_false(actual: Bool) Result[Unit, Error]:

# TDD spelling of `expect_equal` with the same comparison and failure behavior.
export fn assert_equal[T: Equal](actual: T, expected: T) Result[Unit, Error]:

# TDD spelling of `expect_not_equal` with the same comparison and failure behavior.
export fn assert_not_equal[T: Equal](actual: T, expected: T) Result[Unit, Error]:

# TDD spelling of `expect_close` with the same comparison and failure behavior.
export fn assert_close(
    actual: Float,
    expected: Float,
    tolerance: Float
) Result[Unit, Error]:

# TDD spelling of `expect_contains` with the same comparison and failure behavior.
export fn assert_contains(actual: String, expected: String) Result[Unit, Error]:

# TDD spelling of `expect_some` with the same comparison and failure behavior.
export fn assert_some[T](actual: Optional[T]) Result[T, Error]:

# TDD spelling of `expect_none` with the same comparison and failure behavior.
export fn assert_none[T](actual: Optional[T]) Result[Unit, Error]:

# TDD spelling of `expect_ok` with the same comparison and failure behavior.
export fn assert_ok[T, E: Error](actual: Result[T, E]) Result[T, Error]:

# TDD spelling of `expect_error` with the same comparison and failure behavior.
export fn assert_error[T, E: Error](actual: Result[T, E]) Result[E, Error]:

# TDD spelling of `expect_fault`; checks a programming fault and returns its message.
export fn assert_fault(operation: fn() Unit) Result[String, Error]:
