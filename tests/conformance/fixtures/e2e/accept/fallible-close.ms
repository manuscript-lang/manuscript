// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	expect_equal, expect_error, expect_fault from "@std/test/test.ms",
)

type Gate:
	name: String
	fails: Bool

fn var Gate.close() Unit!:
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
	gate.close()?
	return ok(3)

fn loop_exit() Result[Int, Error]:
	for i in [1, 2, 3]:
		_gate := Gate("loop", i == 2)
		if i == 2: break

	return ok(0)

test "a clean close leaves the result alone":
	value := use_gate(false)?
	expect_equal(value, 7)?

test "a failed scope-end close becomes the function's error":
	failure := expect_error(use_gate(true))?
	expect_equal(failure.message, "close a")?

test "the later binding closes first and its error is the one returned":
	both := expect_error(nested(true, true))?
	expect_equal(both.message, "close second")?

	outer_only := expect_error(nested(true, false))?
	expect_equal(outer_only.message, "close first")?

	none := nested(false, false)?
	expect_equal(none, 1)?

test "an explicit close consumes the binding":
	ok_value := explicit(false)?
	expect_equal(ok_value, 3)?

	failure := expect_error(explicit(true))?
	expect_equal(failure.message, "close explicit")?

test "leaving a loop with break closes and returns the error":
	failure := expect_error(loop_exit())?
	expect_equal(failure.message, "close loop")?

type Holder:
	gate: Gate

fn plain(fails: Bool) Int:
	_gate := Gate("plain", fails)
	return 1

fn hold(fails: Bool) Int:
	_holder := Holder(Gate("held", fails))
	return 2

test "a function that cannot return an error faults on a failed close":
	message := expect_fault(fn: _ := plain(true))?
	expect_equal(message, "a resource could not be closed: its close returned an error")?
	expect_equal(plain(false), 1)?

test "a holder closing a part faults on a failed close":
	message := expect_fault(fn: _ := hold(true))?
	expect_equal(message, "a resource could not be closed: its close returned an error")?
	expect_equal(hold(false), 2)?
