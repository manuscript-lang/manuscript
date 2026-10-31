import expect_equal, expect_error, expect_fault from "@std/test.ms"
import Closeable, TextError from "@std/core.ms"

type Gate:
    name: String
    fails: Bool

impl Closeable for Gate:
    var fn close() Unit!:
        if self.fails:
            return error(TextError("close {self.name}"))

        return ok(unit)

fn use_gate(fails: Bool) Result[Int, Error]:
    let _gate = Gate("a", fails)
    return ok(7)

fn nested(outer: Bool, inner: Bool) Result[Int, Error]:
    let _first = Gate("first", outer)
    let _second = Gate("second", inner)
    return ok(1)

fn explicit(fails: Bool) Result[Int, Error]:
    var gate = Gate("explicit", fails)
    try gate.close()
    return ok(3)

fn loop_exit() Result[Int, Error]:
    for i in [1, 2, 3]:
        let _gate = Gate("loop", i == 2)
        if i == 2:
            break

    return ok(0)

test "a clean close leaves the result alone":
    let value = try use_gate(false)
    try expect_equal(value, 7)

test "a failed scope-end close becomes the function's error":
    let failure = try expect_error(use_gate(true))
    try expect_equal(failure.message(), "close a")

test "the later binding closes first and its error is the one returned":
    let both = try expect_error(nested(true, true))
    try expect_equal(both.message(), "close second")

    let outer_only = try expect_error(nested(true, false))
    try expect_equal(outer_only.message(), "close first")

    let none = try nested(false, false)
    try expect_equal(none, 1)

test "an explicit close consumes the binding":
    let ok_value = try explicit(false)
    try expect_equal(ok_value, 3)

    let failure = try expect_error(explicit(true))
    try expect_equal(failure.message(), "close explicit")

test "leaving a loop with break closes and returns the error":
    let failure = try expect_error(loop_exit())
    try expect_equal(failure.message(), "close loop")

type Holder:
    gate: Gate

fn plain(fails: Bool) Int:
    let _gate = Gate("plain", fails)
    return 1

fn hold(fails: Bool) Int:
    let _holder = Holder(Gate("held", fails))
    return 2

test "a function that cannot return an error faults on a failed close":
    let message = try expect_fault(fn: let _ = plain(true))
    try expect_equal(
        message, "a resource could not be closed: its close returned an error"
    )
    try expect_equal(plain(false), 1)

test "a holder closing a part faults on a failed close":
    let message = try expect_fault(fn: let _ = hold(true))
    try expect_equal(
        message, "a resource could not be closed: its close returned an error"
    )
    try expect_equal(hold(false), 2)
