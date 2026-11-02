import TextError from "@std/core.ms"
import expect_equal from "@std/test/test.ms"

# A function that returns an `Error` view and recurses through a contract-type `match` hands
# back the interface value it was given, not a copy freed at the end of the arm.
type Ctx:
    context: String
    cause: Error

impl Error for Ctx:
    fn message() String:
        return self.context.clone()

fn rec(cause: Error) Error:
    match cause:
        Ctx(w): return rec(w.cause)
        _: return cause

test "recursive match returns the root error":
    let w = Ctx("a", Ctx("b", TextError("root")))
    try expect_equal(rec(w).message(), "root")
