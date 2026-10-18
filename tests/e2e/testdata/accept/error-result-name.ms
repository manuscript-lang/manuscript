import {expect_equal, fail} from "@std/testing.ms"

type Result:
    diagnostic: String

impl Error for Result:
    fn message() -> String:
        return self.diagnostic

fn general(value: Result) -> Error:
    return value

test "an application error named Result retains its nominal identity":
    let original = Result("application diagnostic")
    let cause = general(original)
    cause.message() | try expect_equal(expected: "application diagnostic")

    match cause:
        Result(receiver):
            receiver.diagnostic = "changed diagnostic"
        _:
            return fail(message: "application Result lost concrete type")

    original.diagnostic | try expect_equal(expected: "changed diagnostic")
