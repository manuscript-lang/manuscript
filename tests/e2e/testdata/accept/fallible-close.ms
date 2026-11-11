import (
	Closeable from "@std/core.ms",
	expect_equal, expect_error, expect_fault from "@std/test/test.ms",
)

type Gate:
	name: String
	fails: Bool

impl Closeable for Gate:
	var fn close() Unit!:
		if self.fails: return error(Error("close {self.name}"))

fn use_gate(fails: Bool) Result[Int, Error]:
	_gate := Gate("a", fails)
	return ok(7)

fn nested(outer: Bool, inner: Bool) Result[Int, Error]:
	_first := Gate("first", outer)
	_second := Gate("second", inner)
	return ok(1)

fn explicit(fails: Bool) Result[Int, Error]:
	var gate = Gate("explicit", fails)
	try gate.close()
	return ok(3)

fn loop_exit() Result[Int, Error]:
	for i in [1, 2, 3]:
		_gate := Gate("loop", i == 2)
		if i == 2: break

	return ok(0)

test "a clean close leaves the result alone":
	value := try use_gate(false)
	try expect_equal(value, 7)

test "a failed scope-end close becomes the function's error":
	failure := try expect_error(use_gate(true))
	try expect_equal(failure.message, "close a")

test "the later binding closes first and its error is the one returned":
	both := try expect_error(nested(true, true))
	try expect_equal(both.message, "close second")

	outer_only := try expect_error(nested(true, false))
	try expect_equal(outer_only.message, "close first")

	none := try nested(false, false)
	try expect_equal(none, 1)

test "an explicit close consumes the binding":
	ok_value := try explicit(false)
	try expect_equal(ok_value, 3)

	failure := try expect_error(explicit(true))
	try expect_equal(failure.message, "close explicit")

test "leaving a loop with break closes and returns the error":
	failure := try expect_error(loop_exit())
	try expect_equal(failure.message, "close loop")

type Holder:
	gate: Gate

fn plain(fails: Bool) Int:
	_gate := Gate("plain", fails)
	return 1

fn hold(fails: Bool) Int:
	_holder := Holder(Gate("held", fails))
	return 2

test "a function that cannot return an error faults on a failed close":
	message := try expect_fault(fn: _ := plain(true))
	try expect_equal(
		message,
		"a resource could not be closed: its close returned an error",
	)
	try expect_equal(plain(false), 1)

test "a holder closing a part faults on a failed close":
	message := try expect_fault(fn: _ := hold(true))
	try expect_equal(
		message,
		"a resource could not be closed: its close returned an error",
	)
	try expect_equal(hold(false), 2)
