# Assertions for declared test blocks. Each returns a Result whose error describes the failed expectation;
# apply `try` so a test block returns that error and fails. Implementations are native.
# File-level test lifecycle. A local make_fixture() returns its concrete implementer.
# Missing hooks are no-ops. All supplied hooks take no arguments and return Unit.
# Example: a file declares def make_fixture() -> ApiFixture and impl TestHooks for ApiFixture;
# its tests access the shared concrete instance as fixture, and after_all closes its server.
export interface TestHooks:
    # Runs once after the fixture factory and before the file's selected tests.
    var def before_all() -> Unit
    # Runs before each selected test execution, including repetitions.
    var def before_each() -> Unit
    # Runs after each test attempt, including before_each failure, skip, or assertion failure.
    var def after_each() -> Unit
    # Runs once after selected tests finish or stop; also runs when before_all fails.
    var def after_all() -> Unit

# Fails unless actual is True.
export def expect_true(actual: Bool) -> Result[Unit, Error]: ...

# Fails unless actual is False.
export def expect_false(actual: Bool) -> Result[Unit, Error]: ...

# Compares using ordinary Equal semantics; reports expected and actual values on failure.
export def expect_equal[T: Equal](actual: T, expected: T) -> Result[Unit, Error]: ...

# Fails when values are equal under ordinary Equal semantics.
export def expect_not_equal[T: Equal](actual: T, expected: T) -> Result[Unit, Error]: ...

# Checks absolute difference against a finite nonnegative tolerance. NaN fails; identical infinities pass.
export def expect_close(
    actual: Float,
    expected: Float,
    tolerance: Float
) -> Result[Unit, Error]: ...

# Checks for an exact substring without Unicode normalization.
export def expect_contains(actual: String, expected: String) -> Result[Unit, Error]: ...

# Requires some and returns its original payload; fails on none.
export def expect_some[T](actual: Optional[T]) -> Result[T, Error]: ...

# Requires none; fails when a payload is present.
export def expect_none[T](actual: Optional[T]) -> Result[Unit, Error]: ...

# Requires ok and returns its original payload; reports an unexpected error.
export def expect_ok[T, E: Error](actual: Result[T, E]) -> Result[T, Error]: ...

# Requires error and returns its original cause; fails on success.
export def expect_error[T, E: Error](actual: Result[T, E]) -> Result[E, Error]: ...

# Calls operation once, requires a programming fault, and returns its message. Cancellation and skip propagate.
export def expect_fault(operation: Callable[[], Unit]) -> Result[String, Error]: ...

# Returns an error with message; `try fail(message)` fails the current test.
export def fail(message: String) -> Result[Unit, Error]: ...

# Stops and skips the current test, unwinding lexical cleanup. A cleanup failure overrides the skip.
export def skip(reason: String) -> Never: ...

# TDD spelling of `expect_true` with the same comparison and failure behavior.
export def assert_true(actual: Bool) -> Result[Unit, Error]: ...

# TDD spelling of `expect_false` with the same comparison and failure behavior.
export def assert_false(actual: Bool) -> Result[Unit, Error]: ...

# TDD spelling of `expect_equal` with the same comparison and failure behavior.
export def assert_equal[T: Equal](actual: T, expected: T) -> Result[Unit, Error]: ...

# TDD spelling of `expect_not_equal` with the same comparison and failure behavior.
export def assert_not_equal[T: Equal](actual: T, expected: T) -> Result[Unit, Error]: ...

# TDD spelling of `expect_close` with the same comparison and failure behavior.
export def assert_close(
    actual: Float,
    expected: Float,
    tolerance: Float
) -> Result[Unit, Error]: ...

# TDD spelling of `expect_contains` with the same comparison and failure behavior.
export def assert_contains(actual: String, expected: String) -> Result[Unit, Error]: ...

# TDD spelling of `expect_some` with the same comparison and failure behavior.
export def assert_some[T](actual: Optional[T]) -> Result[T, Error]: ...

# TDD spelling of `expect_none` with the same comparison and failure behavior.
export def assert_none[T](actual: Optional[T]) -> Result[Unit, Error]: ...

# TDD spelling of `expect_ok` with the same comparison and failure behavior.
export def assert_ok[T, E: Error](actual: Result[T, E]) -> Result[T, Error]: ...

# TDD spelling of `expect_error` with the same comparison and failure behavior.
export def assert_error[T, E: Error](actual: Result[T, E]) -> Result[E, Error]: ...

# TDD spelling of `expect_fault`; checks a programming fault and returns its message.
export def assert_fault(operation: Callable[[], Unit]) -> Result[String, Error]: ...
