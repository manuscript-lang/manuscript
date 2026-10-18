import {expect_equal, expect_false, fail} from "@std/testing.ms"

type Failure:
    message_text: String

impl Error for Failure:
    fn message() -> String:
        return self.message_text

fn success() -> Result[Optional[Int], Error]:
    return ok(value: some(value: 7))

fn failure() -> Result[Int, Failure]:
    return error(cause: Failure(message_text: "failed"))

fn propagated() -> Result[Int, Error]:
    return ok(value: try failure())

test "prelude cases and optional methods need no imports":
    let inferred = some(value: 3)
    let absent: Optional[Int] = none
    let qualified = Optional[Int].some(value: 5)
    (not inferred.is_some() or not absent.is_none()) | try expect_false
    (inferred.unwrap() != 3 or qualified.unwrap() != 5) | try expect_false
    try expect_false(
        (
            absent.unwrap_or(9) != 9
            or absent.unwrap_or_else(fn() -> Int: return 11) != 11
        )
    )

    match success():
        ok(value):
            try expect_equal(value.unwrap(), 7)
        error(cause): return fail(cause.message())

test "prelude Error preserves concrete failures through try":
    let cause = match propagated():
        ok(value): return fail("failure did not propagate")
        error(cause): cause

    cause.message() | try expect_equal(expected: "failed")

    match cause:
        Failure(value):
            try expect_equal(value.message_text, "failed")
        _: return fail("concrete error lost")
