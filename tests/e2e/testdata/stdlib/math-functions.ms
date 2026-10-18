import {expect_equal, expect_false} from "@std/testing.ms"
import {
    acos,
    asin,
    atan,
    atan2,
    cosh,
    exp,
    log10,
    sinh,
    tan,
    tanh,
    abs,
    pi,
    e,
    remainder
} from "@std/math.ms"

fn near(actual: Float, expected: Float) Bool:
    return abs(actual - expected) < 0.000000001

test "inverse trigonometric functions return radians":
    try expect_false(not near(acos(1.0), 0.0))
    try expect_false(not near(acos(0.0), pi() / 2.0))
    try expect_false(not near(asin(1.0), pi() / 2.0))
    try expect_false(not near(asin(0.0), 0.0))
    try expect_false(not near(atan(1.0), pi() / 4.0))
    try expect_false(not near(atan2(1.0, 1.0), pi() / 4.0))
    try expect_false(not near(atan2(1.0, -1.0), 3.0 * pi() / 4.0))

test "tangent hyperbolic exponential and logarithm functions":
    try expect_false(not near(tan(0.0), 0.0))
    try expect_false(not near(tan(pi() / 4.0), 1.0))
    try expect_false(not near(sinh(0.0), 0.0))
    try expect_false(not near(cosh(0.0), 1.0))
    try expect_false(not near(tanh(0.0), 0.0))
    try expect_false(not near(tanh(1.0), 0.7615941559557649))
    try expect_false(not near(exp(0.0), 1.0))
    try expect_false(not near(exp(1.0), e()))
    try expect_false(not near(log10(1000.0), 3.0))

test "float remainder takes the sign of the dividend":
    try expect_equal(remainder(5.0, 3.0), 2.0)
    try expect_equal(remainder(-5.0, 3.0), -2.0)
    try expect_equal(remainder(7.0, 2.0), 1.0)
    try expect_false(not remainder(5.0, 0.0).is_nan())
