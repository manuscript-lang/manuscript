import TextError from "@std/core.ms"
import expect_equal from "@std/test.ms"
import Decimal from "@std/decimal.ms"

fn amount() Result[Decimal, TextError]:
    return ok(12.50d)

test "explicit standard imports":
    try expect_equal([1, 2].length(), 2)
    try expect_equal(amount().get(0.0d), 12.50d)
