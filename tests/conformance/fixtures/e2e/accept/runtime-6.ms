# conform: tags=decimal,interpolation,modules,optional,stdlib-decimal,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/runtime-6.ms
from "@std/test.ms" import expect_equal, expect_not_equal
from "@std/decimal.ms" import Decimal

def quotient(value: Int, divisor: Int) -> Int:
    return value / divisor

def remainder(value: Int, divisor: Int) -> Int:
    return value % divisor

test "numeric boundary rules":
    try expect_equal(quotient(-7, 2), -3)
    try expect_equal(remainder(-7, 3), -1)
    try expect_equal(remainder(-9223372036854775808, -1), 0)

    let infinity = 1.0 / 0.0
    let nan = 0.0 / 0.0
    try expect_equal(f"{infinity}", "Infinity")
    try expect_not_equal(nan, nan)

    let third = 1d / 3d
    try expect_equal(f"{third}", "0.3333333333333333333333333333333333")

    let absent: Optional[Int] = none
    try expect_equal(1e300.truncate_to_int(), absent)
    try expect_equal((2.seconds + 1.seconds), 3.seconds)
