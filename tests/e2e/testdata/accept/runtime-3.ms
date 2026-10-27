from "@std/core.ms" import TextError
from "@std/test.ms" import expect_equal, expect_true, fail

def identity[T](value: T) -> T:
    return value

def probe() -> Result[Unit, Error]:
    let first = lambda () -> Result[Int, TextError]:
        return ok(3)
    let second = lambda:
        return True
    let number = identity(first)()
    let flag = second()
    (flag) | try expect_true

    match number:
        case ok(value):
            try expect_equal(value, 3)
        case error(_):
            return fail(message: "Unexpected case")

    return ok(())

test "typed callback helper":
    match probe():
        case ok(_):
            let _completed = ()
        case error(_):
            return fail(message: "Unexpected case")

type Code:
    number: Int

impl Error for Code:
    def message() -> String: f"code {self.number}"

def describe(outcome: Result[Int, Code]) -> Result[Int, TextError]:
    match outcome:
        case ok(value):
            return ok(value)
        case error(cause):
            return error(TextError(f"Error {cause.number}"))

test "explicit error conversion":
    let failed: Result[Int, Code] = error(Code(7))
    let expected: Result[Int, TextError] = error(TextError("Error 7"))
    describe(outcome: failed) | try expect_equal(expected)

    let succeeded: Result[Int, Code] = ok(3)
    let unchanged: Result[Int, TextError] = ok(3)
    describe(outcome: succeeded) | try expect_equal(unchanged)
