import (
	Placement, PromiseOptions, caller_frame, promise from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",

	msstd_test_repr from "@std/internal/test.ms",
)

/*
Setup and cleanup for tests that need a fixture. Define `fn make_fixture() T` in the test file,
where `T` implements `TestHooks`; each test accesses the file's one instance as `fixture`.

The file's tests run in order on that instance. The factory and `before_all` run once, the
`*_each` hooks run around every test, and `after_all` runs at the end. A missing hook does
nothing; every hook takes no arguments and returns `Void!`. A hook's error fails the tests it
guards, and an `ESKIP` error (`skip(reason)?`) skips them. A fault in a test runs `after_each`
and `after_all`, and the file's later tests do not run.

For a server fixture, start the server in `before_all` and close it in `after_all`.
*/
export interface TestHooks:
	// Runs once, after the fixture factory, before the file's first test.
	var fn before_all() Void!
	// Runs before each test, including repetitions.
	var fn before_each() Void!
	// Runs after each test, including after a failure, skip or fault.
	var fn after_each() Void!
	// Runs once after the file's last test, and after a fault.
	var fn after_all() Void!

// Returns the position (`file:line:col`) of the call that omitted this argument. Use
// it only as a parameter default, in a function that is called directly.
export fn caller_site() String:
	panic("caller_site() is only valid as a parameter default")

// Internal: builds a failed expectation: an `Error` with `message`, kind `EIO`, and
// the failing call's position in `details["site"]`.
fn failure(message String, site String) Error:
	var details = Map[String, String]()
	details.add("site", site.clone())
	return Error(message.clone(), kind: "EIO", details: details)

// Returns the debug text of a value, with strings quoted and records and collections
// spelled out.
export fn repr[T](value T) String:
	return msstd_test_repr(value)

// Runs `operation` once behind the fault trap and returns the fault message, or
// `null` when it returns normally.
export fn catch_fault(operation fn() Void, site String = caller_frame()) String?:
	result := promise(
		fn: ok(operation()),
		options: PromiseOptions(placement: Placement.Here),
		site: site
	).wait()
	if not result.is_error(): return null

	cause := result.err()
	if cause.kind != "EIO": return null

	return cause.details["report"].split("\n").get(0).clone()

// Fails unless `actual` is true. `site` names the call in the failure and defaults to
// the caller's position.
export fn expect_true(actual Bool, site String = caller_site()) Void!:
	if actual: return ok()
	return error(failure("expected true, got false", site))

// Fails unless `actual` is false. `site` names the call in the failure and defaults
// to the caller's position.
export fn expect_false(actual Bool, site String = caller_site()) Void!:
	if not actual: return ok()
	return error(failure("expected false, got true", site))

// Fails unless `actual` equals `expected` under `Equal`; the failure shows both
// values.
export fn expect_equal[T Equal](actual T, expected T, site String = caller_site()) Void!:
	if actual == expected: return ok()
	return error(failure(f"expected {repr(expected)}, got {repr(actual)}", site))

// Fails when `actual` and `expected` are equal under `Equal`.
export fn expect_not_equal[T Equal](
	actual T,
	expected T,
	site String = caller_site(),
) Void!:
	if actual != expected: return ok()
	return error(failure(f"expected different values, got {repr(actual)}", site))

// Fails unless the absolute difference between `actual` and `expected` is at most
// `tolerance`, which must be finite and not negative. NaN fails; identical infinities
// pass.
export fn expect_close(
	actual Float,
	expected Float,
	tolerance Float,
	site String = caller_site(),
) Void!:
	if not (tolerance >= 0.0 and tolerance - tolerance == 0.0):
		return error(
			failure(
				"expect_close: tolerance must be finite and nonnegative",
				site,
			)
		)
	if actual == expected: return ok()

	var spread = actual - expected
	if spread < 0.0:
		spread = 0.0 - spread
	if spread <= tolerance: return ok()

	return error(
		failure(
			f"expected {repr(expected)} within {repr(tolerance)}, got {repr(actual)}",
			site,
		)
	)

// Fails unless `actual` contains `expected` as an exact substring, without Unicode
// normalization.
export fn expect_contains(
	actual String,
	expected String,
	site String = caller_site(),
) Void!:
	if actual.contains(expected): return ok()
	return error(failure(f"expected {repr(actual)} to contain {repr(expected)}", site))

// Fails on `null`; otherwise returns the payload.
export fn expect_some[T](move actual T?, site String = caller_site()) T!:
	value := actual
	if value != null: return ok(value)

	return error(failure("expected some, got none", site))

// Fails when a value is present; passes on `null`.
export fn expect_none[T](actual T?, site String = caller_site()) Void!:
	value := actual
	if value != null: return error(failure(f"expected none, got {repr(value)}", site))

// Fails on an error, showing it; otherwise returns the `ok` payload.
export fn expect_ok[T, E](move actual T!E, site String = caller_site()) T!:
	if actual.is_error(): return error(
		failure(f"expected ok, got {repr(actual)}", site)
	)
	if value := actual: return ok(value)

	return error(failure("expected ok, got an error", site))

// Fails on success; otherwise returns a copy of the error's cause.
export fn expect_error[T, E Clonable](actual T!E, site String = caller_site()) E!:
	if actual.is_error(): return ok(actual.err().clone())
	return error(failure(f"expected error, got {repr(actual)}", site))

// Calls `operation` once and requires it to raise a programming fault; returns the
// fault message. Fails if the operation returns normally. Cancellation propagates.
export fn expect_fault(operation fn() Void, site String = caller_site()) String!:
	message := catch_fault(operation)
	if message != null: return ok(message)

	return error(
		failure(
			"expected a programming fault, operation returned normally",
			site,
		)
	)

// Returns an error carrying `message`; `fail(message)?` fails the current test.
export fn fail(message String, site String = caller_site()) Void!:
	return error(failure(message, site))

// Skips the current test. It returns an error of kind `ESKIP` with `reason`, which
// `skip(reason)?` passes up; the test is reported as skipped, not failed.
export fn skip(move reason String) Void!:
	return error(Error(reason, kind: "ESKIP"))
