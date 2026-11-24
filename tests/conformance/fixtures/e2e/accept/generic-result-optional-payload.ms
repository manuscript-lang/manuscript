// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

// `ok(value)` into a `T?` field builds a new `some(value)` once `T` is known; it is not a view of `value`.
fn lifted[T](value: T) Result[T?, String]:
	return ok(value)

fn passed[T](value: T?) Result[T?, String]:
	return ok(value)

fn lifted_text(move value: String) Result[String?, String]:
	return ok(value)

test "a generic Result lifts a scalar payload into its optional field":
	expect_equal(lifted(7).get() or panic("called Optional.get() on null"), 7)?

test "a generic Result lifts an owned payload into its optional field":
	expect_equal(
		lifted("hello").get() or panic("called Optional.get() on null"),
		"hello",
	)?
	expect_equal(lifted([1, 2]).get() or panic("called Optional.get() on null"), [1, 2])?

test "a generic Result keeps an optional payload as it is":
	missing: Int? := null
	expect_false(passed(missing).get() != null)?

	present: Int? := 3
	expect_equal(passed(present).get() or panic("called Optional.get() on null"), 3)?

test "a concrete Result lifts a borrowed parameter":
	expect_equal(lifted_text("x").get() or panic("called Optional.get() on null"), "x")?
