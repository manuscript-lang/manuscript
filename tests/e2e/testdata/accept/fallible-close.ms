import expect_equal, expect_error from "@std/test.ms"
import FallibleCloseable, TextError from "@std/core.ms"

type Gate:
    name: String
    fails: Bool

impl FallibleCloseable for Gate:
    var fn close() Result[Unit, Error]:
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
