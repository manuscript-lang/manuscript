import {expect_equal, fail} from "@std/testing.ms"
import Decimal from "@std/decimal.ms"

fn amount() -> Result[Decimal, String]:
    return ok(12.50d)

test "explicit standard imports":
    [1, 2].length() | try expect_equal(expected: 2)

    match amount():
        ok(value):
            try expect_equal(value, 12.50d)
        error(_):
            return fail(message: "Unexpected case")
