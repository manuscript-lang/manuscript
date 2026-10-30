# conform: tags=decimal,modules,stdlib-bigint,stdlib-decimal,stdlib-testing,stdlib-time,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/numeric-boundaries.ms
import expect_equal, expect_false from "@std/test.ms"
import Decimal from "@std/decimal.ms"
import nanoseconds from "@std/time.ms"
import BigInt, BigIntError, from_int from "@std/math.ms"

test "integer division retains signed boundary and remainder rules":
    let minimum = -9223372036854775808
    try expect_false(minimum / 1 != minimum or minimum % -1 != 0)
    try expect_false(-7 / 2 != -3 or - 7 % 3 != -1)
    try expect_false(7 / -2 != -3 or 7 % -3 != 1)
    try expect_false(0 / minimum != 0 or 1 / minimum != 0)
    try expect_equal(1d / -1d, -1d)
    try expect_false((1.0 / 0.0).is_finite() or not (0.0 / 0.0).is_nan())

    let invalid: Result[BigInt, BigIntError] = error(BigIntError.InvalidInput)
    try expect_equal(from_int(1).divide(from_int(0)), invalid)
    try expect_equal(from_int(1).remainder(from_int(0)), invalid)

test "duration arithmetic retains full signed nanosecond range":
    let minimum = nanoseconds(-9223372036854775808)
    let maximum = nanoseconds(9223372036854775807)
    try expect_false(
        (
            minimum.divide(1) != minimum
            or maximum.divide(-1) != nanoseconds((-9223372036854775807))
        )
    )
    try expect_equal(minimum.divide(-9223372036854775808), nanoseconds(1))
    try expect_false(
        (
            minimum.multiply(0) != nanoseconds(0)
            or nanoseconds(0).multiply(-9223372036854775808) != nanoseconds(
                0
            )
        )
    )
    try expect_false(
        (
            minimum.multiply(1) != minimum
            or maximum.multiply(-1) != nanoseconds((-9223372036854775807))
        )
    )
    try expect_equal(
        nanoseconds(-1).multiply(9223372036854775807),
        nanoseconds((-9223372036854775807))
    )
    try expect_false(
        (
            minimum.add(maximum) != nanoseconds(-1)
            or maximum.subtract(maximum) != nanoseconds(0)
        )
    )

test "duration safe addition subtraction negation and unit edges":
    let minimum = nanoseconds(-9223372036854775808)
    let maximum = nanoseconds(9223372036854775807)
    try expect_false(
        (
            minimum.add(nanoseconds(0)) != minimum
            or maximum.subtract(nanoseconds(0)) != maximum
        )
    )
    try expect_false(
        (
            minimum + maximum != nanoseconds(-1)
            or minimum - nanoseconds(-1) != nanoseconds(
                (-9223372036854775807)
            )
        )
    )
    try expect_false(
        (
            nanoseconds(-9223372036854775807).negate() != maximum
            or nanoseconds((-9223372036854775807)).abs() != maximum
        )
    )
    try expect_false(
        (
            nanoseconds(0).negate() != nanoseconds(0)
            or nanoseconds(0).abs() != nanoseconds(0)
        )
    )
    try expect_equal((9223372036854).milliseconds.to_nanoseconds(), 9223372036854000000)
    try expect_equal(
        (-9223372036854).milliseconds.to_nanoseconds(), (-9223372036854000000)
    )
    try expect_false(
        (
            (9223372036).seconds.to_nanoseconds() != 9223372036000000000
            or (
                -9223372036
            ).seconds.to_nanoseconds() != -9223372036000000000
        )
    )
    try expect_false(
        (
            (153722867).minutes.to_nanoseconds() != 9223372020000000000
            or (-153722867).minutes.to_nanoseconds() != -9223372020000000000
        )
    )
