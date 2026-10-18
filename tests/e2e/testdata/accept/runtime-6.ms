import {expect_equal, expect_not_equal} from "@std/testing.ms"
import Decimal from "@std/decimal.ms"

fn quotient(value: Int, divisor: Int) -> Int:
    return value / divisor

fn remainder(value: Int, divisor: Int) -> Int:
    return value % divisor

test "numeric boundary rules":
    quotient(value: -7, divisor: 2) | try expect_equal(expected: -3)
    remainder(value: -7, divisor: 3) | try expect_equal(expected: -1)
    remainder(value: -9223372036854775808, divisor: -1) | try expect_equal(expected: 0)
    let infinity = 1.0 / 0.0
    let nan = 0.0 / 0.0
    "{infinity}" | try expect_equal(expected: "Infinity")
    nan | try expect_not_equal(expected: nan)
    let third = 1d / 3d
    "{third}" | try expect_equal(expected: "0.3333333333333333333333333333333333")
    let absent: Optional[Int] = none
    1e300.truncate_to_int() | try expect_equal(expected: absent)
    (2.seconds + 1.seconds) | try expect_equal(expected: 3.seconds)
