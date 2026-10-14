import Decimal from "@std/decimal.ms"
import {
    abs,
    abs_int,
    ceil,
    floor,
    round,
    truncate,
    sqrt,
    hypot,
    pow,
    log2,
    min,
    max,
    sin,
    cos,
    pi
} from "@std/math.ms"
import panic from "@std/faults.ms"

test "decimal arithmetic is exact and conversion truncates":
    if 0.1d + 0.2d != 0.3d: return panic("decimal precision")
    if 1.00d != 1d: return panic("decimal scale equality")
    if (-1.9d).truncate_to_int() != some(-1): return panic("decimal truncation")
    if 2d.to_float() != 2.0: return panic("decimal float conversion")
    if 123.to_decimal() != 123d: return panic("integer decimal conversion")

test "math rounding signs and exact identities":
    if abs(-2.5) != 2.5 or abs_int(-3) != 3: return panic("absolute value")
    if ceil(-1.5) != -1.0 or floor(-1.5) != -2.0: return panic("signed rounding")
    if round(2.5) != 3.0 or truncate(-1.9) != -1.0: return panic("rounding")
    if sqrt(9.0) != 3.0 or hypot(left: 3.0, right: 4.0) != 5.0: return panic("roots")
    if pow(base: 2.0, exponent: 3.0) != 8.0 or log2(8.0) != 3.0: return panic("powers")
    if min(left: 2.0, right: 3.0) != 2.0 or max(left: 2.0, right: 3.0) != 3.0: return panic(
        "extrema"
    )
    if (
        sin(0.0) != 0.0
        or cos(0.0) != 1.0
        or pi() < 3.14
    ): return panic("trigonometry")
    if not sqrt(-1.0).is_nan(): return panic("NaN predicate")
