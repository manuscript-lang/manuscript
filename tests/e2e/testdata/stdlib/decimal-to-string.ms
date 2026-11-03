import Decimal from "@std/math/decimal.ms"
import expect_equal from "@std/test/test.ms"

test "Decimal.to_string matches its interpolated text":
    for value in [0d, 25.50d, -1.25d, 1e6144d, 1e-6176d]:
        try expect_equal(value.to_string(), "{value}")
    try expect_equal(25.50d.to_string(), "25.5")
