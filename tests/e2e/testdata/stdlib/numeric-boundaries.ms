import {expect_equal, expect_false} from "@std/testing.ms"
import {Duration, duration} from "@std/time.ms"
import Decimal from "@std/decimal.ms"
import {BigInt, BigIntError, from_int} from "@std/bigint.ms"

test "integer division retains signed boundary and remainder rules":
    let minimum = -9223372036854775808
    (minimum / 1 != minimum or minimum % -1 != 0) | try expect_false
    (-7 / 2 != -3 or - 7 % 3 != -1) | try expect_false
    (7 / -2 != -3 or 7 % -3 != 1) | try expect_false
    (0 / minimum != 0 or 1 / minimum != 0) | try expect_false
    (1d / -1d) | try expect_equal(expected: -1d)
    ((1.0 / 0.0).is_finite() or not (0.0 / 0.0).is_nan()) | try expect_false
    let invalid: Result[BigInt, BigIntError] = error(BigIntError.InvalidInput)
    from_int(1).divide(from_int(0)) | try expect_equal(expected: invalid)
    from_int(1).remainder(from_int(0)) | try expect_equal(expected: invalid)

test "duration arithmetic retains full signed nanosecond range":
    let minimum = duration(-9223372036854775808)
    let maximum = duration(9223372036854775807)
    try expect_false(
        (
            minimum.divide(1) != minimum
            or maximum.divide(-1) != duration((-9223372036854775807))
        )
    )
    minimum.divide(-9223372036854775808) | try expect_equal(expected: duration(1))
    try expect_false(
        (
            minimum.multiply(0) != duration(0)
            or duration(0).multiply(-9223372036854775808) != duration(0)
        )
    )
    try expect_false(
        (
            minimum.multiply(1) != minimum
            or maximum.multiply(-1) != duration((-9223372036854775807))
        )
    )
    duration(-1).multiply(9223372036854775807) | try expect_equal(
        expected: duration((-9223372036854775807))
    )
    try expect_false(
        (
            minimum.add(maximum) != duration(-1)
            or maximum.subtract(maximum) != duration(0)
        )
    )

test "duration safe addition subtraction negation and unit edges":
    let minimum = duration(-9223372036854775808)
    let maximum = duration(9223372036854775807)
    try expect_false(
        (
            minimum.add(duration(0)) != minimum
            or maximum.subtract(duration(0)) != maximum
        )
    )
    try expect_false(
        (
            minimum + maximum != duration(-1)
            or minimum - duration(-1) != duration((-9223372036854775807))
        )
    )
    try expect_false(
        (
            duration(-9223372036854775807).negate() != maximum
            or duration((-9223372036854775807)).abs() != maximum
        )
    )
    try expect_false(
        (
            duration(0).negate() != duration(0)
            or duration(0).abs() != duration(0)
        )
    )
    (
        (9223372036854).milliseconds.to_nanoseconds() | try expect_equal(
            expected: 9223372036854000000
        )
    )
    (
        (-9223372036854).milliseconds.to_nanoseconds() | try expect_equal(
            expected: (-9223372036854000000)
        )
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
