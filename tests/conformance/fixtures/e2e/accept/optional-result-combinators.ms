// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

type Counter:
	calls: Int

type Wrapped:
	inner: String

fn Wrapped.message() String: "wrapped {self.inner}"

fn tick(var counter: Counter) Int:
	counter.calls += 1
	return 7

fn widen(cause: Error) Wrapped: Wrapped(cause.message)

fn parse(ok_value: Bool) Int!Error:
	if ok_value: return ok(5)
	return error(Error("bad"))

fn convert(ok_value: Bool) Int!Wrapped:
	value := parse(ok_value).map_error(widen)?
	return ok(value + 1)

fn unexpected_int() Int: panic("closure must not run")

fn unexpected_optional() Int?: panic("closure must not run")

fn unexpected_recover(cause: Error) Int!Error:
	return panic("closure must not run")

fn unexpected_text(cause: Error) Int: panic("closure must not run")

fn unexpected_widen(cause: Error) Wrapped: panic("closure must not run")

test "Optional get_or_else returns the payload and is lazy":
	present: Int? := 0
	missing: Int? := none
	var counter = Counter(0)
	expect_equal(present.get_or_else(unexpected_int), 0)?
	expect_equal(missing.get_or_else(fn: tick(var counter)), 7)?
	expect_equal(counter.calls, 1)?

	flag: Bool? := false
	expect_false(flag.get_or_else(fn: true))?

test "Optional or_else keeps the wrapper and is lazy":
	present: Int? := 0
	missing: Int? := none
	expect_equal(present.or_else(unexpected_optional), 0)?
	expect_equal(missing.or_else(fn: 4), 4)?
	expect_equal(missing.or_else(fn: none), none)?

test "Result get_or_else returns the payload and receives the error":
	success: Int!Error := ok(0)
	failure: Int!Error := error(Error("failed"))
	expect_equal(success.get_or_else(unexpected_text), 0)?
	expect_equal(failure.get_or_else(fn cause: cause.message.scalar_length()), 6)?

test "Result or_else keeps the wrapper and is lazy":
	success: Int!Error := ok(1)
	failure: Int!Error := error(Error("failed"))
	expect_equal(success.or_else(unexpected_recover), success)?
	expect_equal(failure.or_else(fn cause: ok(9)), ok(9))?

	still: Int!Error := failure.or_else(fn cause: error(Error("again")))
	expect_equal(still.err().message, "again")?

test "Result map_error converts the error type and feeds try":
	success: Int!Error := ok(3)
	failure: Int!Error := error(Error("bad"))
	expect_equal(success.map_error(unexpected_widen).get(), 3)?
	expect_equal(failure.map_error(widen).err().inner, "bad")?
	expect_equal(convert(true).get(), 6)?
	expect_equal(convert(false).err().message(), "wrapped bad")?

test "map and and_then on both types keep their meaning":
	present: Int? := 2
	success: Int!Error := ok(2)
	expect_equal(present.map(fn n: n + 1).get(), 3)?
	expect_equal(present.and_then(fn(n: Int) Int?: n * 2).get(), 4)?
	expect_equal(success.map(fn n: n + 1).get(), 3)?
	expect_equal(success.and_then(fn n: ok(n * 2)).get(), 4)?
