import Decimal from "@std/decimal.ms"
import panic from "@std/faults.ms"
import {duration} from "@std/time.ms"
import {BigInt, BigIntError, from_int} from "@std/bigint.ms"

test "integer division retains signed boundary and remainder rules":
    let minimum = -9223372036854775808
    if minimum / 1 != minimum or minimum % -1 != 0: return panic("minimum boundary")
    if - 7 / 2 != -3 or - 7 % 3 != -1: return panic("negative dividend")
    if 7 / -2 != -3 or 7 % -3 != 1: return panic("negative divisor")
    if 0 / minimum != 0 or 1 / minimum != 0: return panic("minimum divisor")
    if 1d / -1d != -1d: return panic("decimal division")
    if (1.0 / 0.0).is_finite() or not (0.0 / 0.0).is_nan(): return panic(
        "IEEE zero division"
    )

    let invalid: Result[BigInt, BigIntError] = error(BigIntError.InvalidInput)
    if from_int(1).divide(from_int(0)) != invalid: return panic("BigInt domain error")
    if from_int(1).remainder(from_int(0)) != invalid: return panic(
        "BigInt remainder error"
    )

test "duration arithmetic retains full signed nanosecond range":
    let minimum = duration(-9223372036854775808)
    let maximum = duration(9223372036854775807)
    if (
        minimum.divide(1) != minimum
        or maximum.divide(-1) != duration((-9223372036854775807))
    ): return panic("duration divide bounds")
    if minimum.divide(-9223372036854775808) != duration(1): return panic(
        "duration minimum divisor"
    )
    if (
        minimum.multiply(0) != duration(0)
        or duration(0).multiply(-9223372036854775808) != duration(0)
    ): return panic("zero multiplication")
    if (
        minimum.multiply(1) != minimum
        or maximum.multiply(-1) != duration((-9223372036854775807))
    ): return panic("multiplication boundaries")
    if duration(-1).multiply(9223372036854775807) != duration(-9223372036854775807): return panic(
        "negative multiplication"
    )
    if minimum.add(maximum) != duration(-1) or maximum.subtract(maximum) != duration(0): return panic(
        "signed addition/subtraction"
    )

test "duration safe addition subtraction negation and unit edges":
    let minimum = duration(-9223372036854775808)
    let maximum = duration(9223372036854775807)
    if minimum.add(duration(0)) != minimum or maximum.subtract(duration(0)) != maximum: return panic(
        "zero operand"
    )
    if (
        minimum + maximum != duration(-1)
        or minimum - duration(-1) != duration((-9223372036854775807))
    ): return panic("duration operators")
    if (
        duration(-9223372036854775807).negate() != maximum
        or duration((-9223372036854775807)).abs() != maximum
    ): return panic("unary boundary")
    if duration(0).negate() != duration(0) or duration(0).abs() != duration(0): return panic(
        "zero unary"
    )
    if (9223372036854).milliseconds.to_nanoseconds() != 9223372036854000000: return panic(
        "milliseconds maximum"
    )
    if (-9223372036854).milliseconds.to_nanoseconds() != -9223372036854000000: return panic(
        "milliseconds minimum"
    )
    if (
        (9223372036).seconds.to_nanoseconds() != 9223372036000000000
        or (-9223372036).seconds.to_nanoseconds() != -9223372036000000000
    ): return panic("seconds edges")
    if (
        (153722867).minutes.to_nanoseconds() != 9223372020000000000
        or (-153722867).minutes.to_nanoseconds() != -9223372020000000000
    ): return panic("minutes edges")
