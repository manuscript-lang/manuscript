import {expect_equal} from "@std/testing.ms"

type Failure:
    code: Int

impl Error for Failure:
    fn message() -> String:
        return "failure " + self.code.toString()

fn failing() -> Result[Int, Failure]:
    return error(Failure(code: 7))

fn succeeding() -> Result[Int, Failure]:
    return ok(3)

fn describe[T](r: Result[T, Error]) -> String:
    match r:
        ok(_):
            return "ok"
        error(cause):
            return cause.message()

test "a generic Result[T, Error] parameter infers T and widens a domain error":
    describe(r: failing()) | try expect_equal(expected: "failure 7")
    describe(r: succeeding()) | try expect_equal(expected: "ok")
