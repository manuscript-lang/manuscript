# conform: tags=closures,control-flow,faults,interfaces,match,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/prelude.ms
from "@std/test.ms" import expect_equal, expect_false, fail

type Failure:
    message_text: String

impl Error for Failure:
    def message() -> String:
        return self.message_text.clone()

def success() -> Result[Optional[Int], Error]:
    return ok(some(7))

def failure() -> Result[Int, Failure]:
    return error(Failure("failed"))

def propagated() -> Result[Int, Error]:
    return ok(try failure())

test "prelude cases and optional methods need no imports":
    let inferred = some(3)
    let absent: Optional[Int] = none
    let qualified = Optional[Int].some(5)
    try expect_false(not inferred.is_some() or not absent.is_none())
    try expect_false(inferred.get() != 3 or qualified.get() != 5)
    try expect_false(
        (
            absent.get(9) != 9
            or absent.or_else(
                lambda () -> Optional[Int]: return some(11)
            ).get() != 11
        )
    )

    let value = try success()
    try expect_equal(value.get(), 7)

test "prelude Error preserves concrete failures through try":
    let outcome = propagated()
    try expect_false(not outcome.is_error())

    let cause = outcome.err()
    try expect_equal(cause.message(), "failed")

    match cause:
        case Failure(value):
            try expect_equal(value.message_text, "failed")
        case _: return fail("concrete error lost")
