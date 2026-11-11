// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false from "@std/test/test.ms"

// `ok(value)` into a `T?` field builds a new `some(value)` once `T` is known; it is not a view of `value`.
fn lifted[T](value: T) Result[T?, String]:
	return ok(value)

fn passed[T](value: T?) Result[T?, String]:
	return ok(value)

fn lifted_text(value: String) Result[String?, String]:
	return ok(value)

test "a generic Result lifts a scalar payload into its optional field":
	expect_equal(lifted(7).get().get(), 7)?

test "a generic Result lifts an owned payload into its optional field":
	expect_equal(lifted("hello").get().get(), "hello")?
	expect_equal(lifted([1, 2]).get().get(), [1, 2])?

test "a generic Result keeps an optional payload as it is":
	missing: Int? := none
	expect_false(passed(missing).get().is_some())?

	present: Int? := 3
	expect_equal(passed(present).get().get(), 3)?

test "a concrete Result lifts a borrowed parameter":
	expect_equal(lifted_text("x").get().get(), "x")?
