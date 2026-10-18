import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
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

test "decimal arithmetic is exact and conversion truncates":
    (0.1d + 0.2d) | try expect_equal(expected: 0.3d)
    1.00d | try expect_equal(expected: 1d)
    (-1.9d).truncate_to_int() | try expect_equal(expected: some(-1))
    2d.to_float() | try expect_equal(expected: 2.0)
    123.to_decimal() | try expect_equal(expected: 123d)

test "math rounding signs and exact identities":
    (abs(-2.5) != 2.5 or abs_int(-3) != 3) | try expect_false
    (ceil(-1.5) != -1.0 or floor(-1.5) != -2.0) | try expect_false
    (round(2.5) != 3.0 or truncate(-1.9) != -1.0) | try expect_false
    (sqrt(9.0) != 3.0 or hypot(left: 3.0, right: 4.0) != 5.0) | try expect_false
    (pow(base: 2.0, exponent: 3.0) != 8.0 or log2(8.0) != 3.0) | try expect_false
    (min(left: 2.0, right: 3.0) != 2.0 or max(left: 2.0, right: 3.0) != 3.0) | try expect_false
    (sin(0.0) != 0.0 or cos(0.0) != 1.0 or pi() < 3.14) | try expect_false
    (sqrt(-1.0).is_nan()) | try expect_true
