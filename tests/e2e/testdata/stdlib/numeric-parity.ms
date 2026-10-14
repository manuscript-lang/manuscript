import {
    min_int,
    max_int,
    pow_int,
    sign,
    sign_int,
    clamp,
    clamp_int,
    cbrt,
    asinh,
    acosh,
    atanh,
    round_to_int,
    floor_to_int,
    ceil_to_int,
    sum_int,
    sum_float
} from "@std/math.ms"
import {BigInt, BigIntError, from_int} from "@std/bigint.ms"
import Decimal from "@std/decimal.ms"
import {NumberError, parse_float} from "@std/numbers.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "integer math retains signed 64 bit boundaries and checked powers":
    let minimum = -9223372036854775808
    let maximum = 9223372036854775807
    if min_int(maximum, minimum) != minimum or max_int(minimum, maximum) != maximum:
        return panic("integer extrema rounded through Float")
    if value(pow_int(-2, 63)) != minimum or value(pow_int(maximum, 1)) != maximum:
        return panic("exact signed boundary power")
    if value(pow_int(0, 0)) != 1 or value(pow_int(-1, maximum)) != -1:
        return panic("power identity")

    let overflow: Result[Int, NumberError] = error(NumberError.OutOfRange)
    if pow_int(2, 63) != overflow or pow_int(minimum, 2) != overflow:
        return panic("unchecked integer power overflow")

    let invalid: Result[Int, NumberError] = error(NumberError.InvalidInput)
    if pow_int(2, -1) != invalid: return panic("negative integer exponent")
    if clamp_int(minimum, -5, 5) != -5 or clamp_int(maximum, -5, 5) != 5:
        return panic("integer clamping")
    if (
        sign_int(minimum) != -1
        or sign_int(maximum) != 1
        or sign_int(0) != 0
    ):
        return panic("integer signs")

test "floating math preserves domain values and signed zero":
    if (
        cbrt(-8.0) != -2.0
        or asinh(0.0) != 0.0
        or acosh(1.0) != 0.0
        or atanh(0.0) != 0.0
    ):
        return panic("root and inverse hyperbolic identities")
    if not acosh(0.5).is_nan() or atanh(1.0).is_finite():
        return panic("inverse hyperbolic domains")
    if (
        sign(-0.0).to_string() != "-0"
        or sign(-3.0) != -1.0
        or sign(3.0) != 1.0
    ):
        return panic("floating signs")
    if clamp(3.0, -2.0, 2.0) != 2.0 or clamp(-3.0, -2.0, 2.0) != -2.0:
        return panic("floating clamping")
    if not clamp(
        value(parse_float("NaN")),
        -2.0,
        2.0
    ).is_nan():
        return panic("clamping NaN")

test "float integer conversions expose rounded range failures":
    if (
        round_to_int(-1.5) != some(-1)
        or floor_to_int(-1.5) != some(-2)
        or ceil_to_int((-1.5)) != some((-1))
    ):
        return panic("floating rounding rules")
    if (
        (-1.5).round_to_int() != some(-1)
        or (-1.5).floor_to_int() != some(-2)
        or (-1.5).ceil_to_int() != some((-1))
    ):
        return panic("floating receiver conversions")

    let rounded = (-1.5).round_to_int
    if rounded() != some(-1): return panic("stored floating conversion")
    if (-9223372036854775808.0).round_to_int() != some(-9223372036854775808):
        return panic("minimum floating conversion")
    if not 9223372036854775808.0.round_to_int().is_none():
        return panic("upper floating boundary rounded into Int")

    for text in ["NaN", "Infinity", "-Infinity"]:
        let nonfinite = value(parse_float(text))
        if (
            not nonfinite.round_to_int().is_none()
            or not nonfinite.floor_to_int().is_none()
            or not nonfinite.ceil_to_int().is_none()
        ):
            return panic("nonfinite conversion")

test "big integer unary powers and shifts preserve input aliases":
    let negative = from_int(-7)
    let alias = negative
    if negative.negate().to_int() != some(7) or negative.abs().to_int() != some(7):
        return panic("big integer unary signs")
    if negative.bit_not().to_int() != some(6): return panic(
        "infinite signed complement"
    )
    if (
        value(negative.pow(3)).to_int() != some(-343)
        or value(negative.pow(3, none)).to_int() != some((-343))
    ):
        return panic("omitted or none power budget")
    if value(negative.pow(3, max_bits: 9)).to_int() != some(-343):
        return panic("explicit bit budget")

    let powered = negative.pow
    if value(powered(3)).to_int() != some(-343): return panic("stored power defaults")

    let typed: fn(exponent: Int, max_bits: Optional[Int]) -> Result[BigInt, BigIntError] = negative.pow
    if value(typed(3, 9)).to_int() != some(-343): return panic("typed power method")
    if value(negative.shift_left(2)).to_int() != some(-28): return panic(
        "signed left shift"
    )
    if value(negative.shift_right(1)).to_int() != some(-4): return panic(
        "arithmetic right shift"
    )
    if value(negative.shift_right(9223372036854775807)).to_int() != some(-1):
        return panic("large negative right shift")
    if value(from_int(7).shift_right(9223372036854775807)).to_int() != some(0):
        return panic("large positive right shift")
    if negative.to_int() != some(-7) or alias.to_int() != some(-7):
        return panic("numeric operation mutated an alias")

test "big integer growth rejects invalid requests and excessive output":
    let invalid: Result[BigInt, BigIntError] = error(BigIntError.InvalidInput)
    let limited: Result[BigInt, BigIntError] = error(BigIntError.LimitExceeded)
    if from_int(2).pow(-1) != invalid or from_int(2).pow(3, -1) != invalid:
        return panic("negative power request")
    if from_int(2).shift_left(-1) != invalid or from_int(2).shift_right(-1) != invalid:
        return panic("negative shift request")
    if from_int(2).shift_left(1, -1) != invalid: return panic("negative bit budget")
    if from_int(-7).pow(3, 8) != limited or from_int(-7).shift_left(2, 4) != limited:
        return panic("supplied magnitude budget")
    if from_int(2).pow(9223372036854775807) != limited:
        return panic("unbounded native power allocation")
    if from_int(1).shift_left(9223372036854775807) != limited:
        return panic("unbounded native shift allocation")
    if value(from_int(0).shift_left(9223372036854775807, 0)).to_int() != some(0):
        return panic("zero shift exceeded zero magnitude budget")
    if value(from_int(0).pow(9223372036854775807, 0)).to_int() != some(0):
        return panic("zero power exceeded zero magnitude budget")
    if value(from_int(0).pow(0)).to_int() != some(1): return panic("zero to zero power")

test "decimal integer rounding stays exact past binary float precision":
    if 9007199254740993.1d.floor_to_int() != some(9007199254740993):
        return panic("decimal rounding used Float")
    if 2.5d.round_to_int() != some(2) or 3.5d.round_to_int() != some(4):
        return panic("decimal HalfEven ties")
    if (-2.5d).round_to_int() != some(-2) or (-3.5d).round_to_int() != some(-4):
        return panic("negative decimal HalfEven ties")
    if (-1.5d).floor_to_int() != some(-2) or (-1.5d).ceil_to_int() != some(-1):
        return panic("decimal directional rounding")
    if (-9223372036854775808.5d).round_to_int() != some(-9223372036854775808):
        return panic("minimum decimal tie")
    if (
        not 9223372036854775807.5d.round_to_int().is_none()
        or not (-9223372036854775808.1d).floor_to_int().is_none()
    ):
        return panic("decimal integer overflow")

    let rounded = 2.5d.round_to_int
    if rounded() != some(2): return panic("stored exact conversion")
    if (-9007199254740993.1d).abs() != 9007199254740993.1d:
        return panic("decimal magnitude")
    if 9007199254740993d.compare(9007199254740992d) != 1:
        return panic("decimal comparison used Float")

test "numeric sums retain input values running overflow and IEEE arithmetic":
    let integers = [-9223372036854775808, 9223372036854775807]
    if value(sum_int(integers)) != -1: return panic("signed sum boundary")
    if integers != [-9223372036854775808, 9223372036854775807]:
        return panic("sum changed input")
    if value(sum_int([])) != 0 or sum_float([]) != 0.0:
        return panic("empty sum identity")
    if value(
        sum_int([9223372036854775807, -1, 1])
    ) != 9223372036854775807:
        return panic("maximum running total")

    let overflow: Result[Int, NumberError] = error(NumberError.OutOfRange)
    if sum_int([-9223372036854775808, -1]) != overflow:
        return panic("negative sum overflow")
    if sum_int([9223372036854775807, 1, -1]) != overflow:
        return panic("running total overflow")
    if sum_float([1.5, -2.0, 3.0]) != 2.5: return panic("floating sum")
    if not sum_float([value(parse_float("Infinity")), value(parse_float("-Infinity"))]).is_nan():
        return panic("IEEE sum")
