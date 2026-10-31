import Decimal from "@std/decimal.ms"
import expect_equal from "@std/test.ms"

test "decimal zero identities preserve signs and exponent extremes":
    for value in [
        0d, 1.25d, -1.25d, 1e6144d, -1e6144d, 1e-6176d, -1e-6176d,
        9.999999999999999999999999999999999e6144d
    ]:
        try expect_equal(value + 0d, value)
        try expect_equal(0d + value, value)
        try expect_equal(value - 0d, value)
        try expect_equal(0d - value, -value)

    try expect_equal(1.25d + -1.25d, 0d)
