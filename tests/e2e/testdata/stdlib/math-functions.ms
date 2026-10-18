import {expect_true} from "@std/testing.ms"
import {acos, asin, atan, atan2, cosh, exp, log10, sinh, tan, tanh, abs, pi, e} from "@std/math.ms"

fn near(actual: Float, expected: Float) -> Bool:
    return abs(actual - expected) < 0.000000001

test "inverse trigonometric functions return radians":
    (near(acos(1.0), 0.0)) | try expect_true
    (near(acos(0.0), pi() / 2.0)) | try expect_true
    (near(asin(1.0), pi() / 2.0)) | try expect_true
    (near(asin(0.0), 0.0)) | try expect_true
    (near(atan(1.0), pi() / 4.0)) | try expect_true
    (near(atan2(1.0, 1.0), pi() / 4.0)) | try expect_true
    (near(atan2(1.0, -1.0), 3.0 * pi() / 4.0)) | try expect_true

test "tangent hyperbolic exponential and logarithm functions":
    (near(tan(0.0), 0.0)) | try expect_true
    (near(tan(pi() / 4.0), 1.0)) | try expect_true
    (near(sinh(0.0), 0.0)) | try expect_true
    (near(cosh(0.0), 1.0)) | try expect_true
    (near(tanh(0.0), 0.0)) | try expect_true
    (near(tanh(1.0), 0.7615941559557649)) | try expect_true
    (near(exp(0.0), 1.0)) | try expect_true
    (near(exp(1.0), e())) | try expect_true
    (near(log10(1000.0), 3.0)) | try expect_true
