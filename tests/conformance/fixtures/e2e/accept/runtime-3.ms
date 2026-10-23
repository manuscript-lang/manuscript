# conform: tags=closures,control-flow,generics,interfaces,interpolation,match,modules,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/runtime-3.ms
import {TextError} from "@std/core.ms"
import {expect_equal, expect_true, fail} from "@std/testing.ms"

fn identity[T](value: T) T:
    return value

fn probe() Result[Unit, Error]:
    let first = fn() Result[Int, TextError]:
        return ok(3)
    let second = fn():
        return true
    let number = identity(first)()
    let flag = second()
    (flag) | try expect_true

    match number:
        ok(value):
            try expect_equal(value, 3)
        error(_):
            return fail(message: "Unexpected case")

    return ok(unit)

test "typed callback helper":
    match probe():
        ok(_):
            let completed = unit
        error(_):
            return fail(message: "Unexpected case")

type Code:
    number: Int

impl Error for Code:
    fn message() String: "code {self.number}"

fn describe(outcome: Result[Int, Code]) Result[Int, TextError]:
    match outcome:
        ok(value):
            return ok(value)
        error(cause):
            return error(TextError("Error {cause.number}"))

test "explicit error conversion":
    let failed: Result[Int, Code] = error(Code(7))
    let expected: Result[Int, TextError] = error(TextError("Error 7"))
    describe(outcome: failed) | try expect_equal(expected)

    let succeeded: Result[Int, Code] = ok(3)
    let unchanged: Result[Int, TextError] = ok(3)
    describe(outcome: succeeded) | try expect_equal(unchanged)
