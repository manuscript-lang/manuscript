import panic from "@std/core.ms"
import (msstd_test_catch_fault, msstd_test_repr) from "@std/internal/test.ms"

/*
Setup and cleanup for tests that need a fixture. Define `fn make_fixture() T` in the test file,
where `T` implements `TestHooks`; each test accesses its own instance as `fixture`.
Each selected test and repetition runs in a fresh process, so the factory and all hooks run again.
Missing hooks are no-ops. All supplied hooks take no arguments and return Unit.
For a server fixture, start the server in the factory and close it in `after_all`.
Tests share the fixture definition, not one running server or mutable instance.
*/
export interface TestHooks:
    // Runs after the fixture factory in each selected test process.
    var fn before_all() Unit
    // Runs before each selected test execution, including repetitions.
    var fn before_each() Unit
    // Runs after each test attempt, including before_each failure, skip, or assertion failure.
    var fn after_each() Unit
    // Runs after the test finishes or stops in its process; also runs when before_all fails.
    var fn after_all() Unit

// The position (`file:line:col`) of the call that omitted this argument. Valid only as a parameter default, in a function called directly.
export fn caller_site() String:
    panic("caller_site() is only valid as a parameter default")

// A failed expectation: `message`, kind EIO, and the failing call's position in `details["site"]`.
fn failure(message: String, site: String) Error:
    var details = Map[String, String]()
    details.add("site", site)
    return Error(message, kind: "EIO", details: details)

// The debug text of a value, with strings quoted and records and collections spelled out.
export fn repr[T](value: T) String:
    return msstd_test_repr(value)

// Runs operation once behind the fault trap and returns the fault message, or none when it returns normally.
export fn catch_fault(operation: fn() Unit) String?:
    return msstd_test_catch_fault(operation)

// Fails unless actual is True. `site` names the call in the failure and defaults to the caller's position.
export fn expect_true(actual: Bool, site: String = caller_site()) Unit!:
    if actual: return ok(unit)

    return error(failure("expected true, got false", site))

// Fails unless actual is False. `site` names the call in the failure and defaults to the caller's position.
export fn expect_false(actual: Bool, site: String = caller_site()) Unit!:
    if not actual: return ok(unit)

    return error(failure("expected false, got true", site))

// Compares using ordinary Equal semantics; reports expected and actual values on failure.
export fn expect_equal[T: Equal](
    actual: T,
    expected: T,
    site: String = caller_site()
) Unit!:
    if actual == expected: return ok(unit)

    return error(failure("expected {repr(expected)}, got {repr(actual)}", site))

// Fails when values are equal under ordinary Equal semantics.
export fn expect_not_equal[T: Equal](
    actual: T,
    expected: T,
    site: String = caller_site()
) Unit!:
    if actual != expected: return ok(unit)

    return error(failure("expected different values, got {repr(actual)}", site))

// Checks absolute difference against a finite nonnegative tolerance. NaN fails; identical infinities pass.
export fn expect_close(
    actual: Float,
    expected: Float,
    tolerance: Float,
    site: String = caller_site()
) Unit!:
    if not (tolerance >= 0.0 and tolerance - tolerance == 0.0):
        return error(
            failure(
                "expect_close: tolerance must be finite and nonnegative", site
            )
        )
    if actual == expected: return ok(unit)

    var spread = actual - expected
    if spread < 0.0:
        spread = 0.0 - spread
    if spread <= tolerance: return ok(unit)

    return error(
        failure(
            "expected {repr(expected)} within {repr(tolerance)}, got {repr(actual)}",
            site
        )
    )

// Checks for an exact substring without Unicode normalization.
export fn expect_contains(
    actual: String,
    expected: String,
    site: String = caller_site()
) Unit!:
    if actual.contains(expected): return ok(unit)

    return error(failure("expected {repr(actual)} to contain {repr(expected)}", site))

// Requires some and returns its original payload; fails on none.
export fn expect_some[T](actual: T?, site: String = caller_site()) T!:
    if let value = actual: return ok(value)

    return error(failure("expected some, got none", site))

// Requires none; fails when a payload is present.
export fn expect_none[T](actual: T?, site: String = caller_site()) Unit!:
    if let value = actual:
        return error(failure("expected none, got {repr(value)}", site))

    return ok(unit)

// Requires ok and returns its original payload; reports an unexpected error.
export fn expect_ok[T, E](actual: T!E, site: String = caller_site()) T!:
    if actual.is_error(): return error(failure("expected ok, got {repr(actual)}", site))
    if let value = actual: return ok(value)

    return error(failure("expected ok, got an error", site))

// Requires error and returns its original cause; fails on success.
export fn expect_error[T, E: Clonable](actual: T!E, site: String = caller_site()) E!:
    if actual.is_error(): return ok(actual.err().clone())

    return error(failure("expected error, got {repr(actual)}", site))

// Calls operation once, requires a programming fault, and returns its message. Cancellation and skip propagate.
export fn expect_fault(operation: fn() Unit, site: String = caller_site()) String!:
    if let message = catch_fault(operation): return ok(message)

    return error(
        failure(
            "expected a programming fault, operation returned normally", site
        )
    )

// Returns an error with message; `try fail(message)` fails the current test.
export fn fail(message: String, site: String = caller_site()) Unit!:
    return error(failure(message, site))

// Stops and skips the current test, unwinding lexical cleanup. A cleanup failure overrides the skip.
export fn skip(reason: String) Never:
    panic("\u{1}SKIP\u{1}{reason}")
