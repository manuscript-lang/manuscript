# conform: tags=control-flow,faults,interfaces,lists,match,modules,numbers,records,stdlib-math,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/math-functions.ms
import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import {
    acos, asin, atan, atan2, cosh, exp, log10, sinh, tan, tanh, abs, pi, e, remainder,
    max, min, max_of, min_of, acosh, asinh, atanh, cbrt, expm1, log1p, sign, sign_int,
    to_float32, is_integer, is_safe_integer, infinity, nan, epsilon, max_float,
    min_float, max_int, min_int, max_safe_integer, min_safe_integer, ln2, ln10, log2e,
    log10e, sqrt2, sqrt_half
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

type Ranked:
    rank: Int
    unexpected: List[Int] = []

impl Comparable for Ranked:
    fn compare(other: Comparable) Int:
        match other:
            Ranked(value):
                if self.rank < value.rank: return -9223372036854775808
                if self.rank > value.rank: return 9223372036854775807

                return 0
            _:
                return 0

test "extrema use comparator signs without negating Int minimum":
    let low = Ranked(1)
    let high = Ranked(2)
    try expect_equal(min(high.clone(), low.clone()).rank, 1)
    try expect_equal(max(low.clone(), high.clone()).rank, 2)

    for values in [[high.clone(), low.clone()], [low.clone(), high.clone()]]:
        try expect_equal(min_of(values.clone()).get().rank, 1)
        try expect_equal(max_of(values.clone()).get().rank, 2)

    let values = [high.clone(), low.clone(), Ranked(1), Ranked(2)]
    var minimum = min_of(values.clone()).get().clone()
    var maximum = max_of(values.clone()).get().clone()
    minimum.rank = 0
    maximum.rank = 3
    try expect_false(values[1].rank != 1 or values[2].rank != 1)
    try expect_false(values[0].rank != 2 or values[3].rank != 2)
    for value in values:
        try expect_false(not value.unexpected.is_empty())

test "inverse hyperbolic cube root and precision helpers":
    try expect_true(near(acosh(1.0), 0.0))
    try expect_true(near(asinh(0.0), 0.0))
    try expect_true(near(atanh(0.0), 0.0))
    try expect_true(atanh(1.0) == infinity())
    try expect_true(acosh(0.5).is_nan())
    try expect_true(near(cbrt(27.0), 3.0))
    try expect_true(near(cbrt(-8.0), -2.0))
    try expect_true(near(expm1(0.0), 0.0))
    try expect_true(near(log1p(0.0), 0.0))
    try expect_true(near(log1p(1.0), ln2()))

test "sign and integer predicates":
    try expect_equal(sign(-3.5), -1.0)
    try expect_equal(sign(2.0), 1.0)
    try expect_true(sign(nan()).is_nan())
    try expect_equal(sign_int(-9), -1)
    try expect_equal(sign_int(0), 0)
    try expect_equal(sign_int(12), 1)
    try expect_true(is_integer(4.0))
    try expect_false(is_integer(4.5))
    try expect_false(is_integer(infinity()))
    try expect_false(is_integer(nan()))
    try expect_true(is_safe_integer(9007199254740991.0))
    try expect_false(is_safe_integer(9007199254740992.0))
    try expect_equal(to_float32(0.1) == 0.1, false)

test "numeric limits and constants match IEEE and JavaScript":
    try expect_true(infinity() > max_float())
    try expect_true(nan().is_nan())
    try expect_equal(1.0 + epsilon() > 1.0, true)
    try expect_equal(1.0 + epsilon() / 2.0 > 1.0, false)
    try expect_true(min_float() > 0.0)
    try expect_equal(max_safe_integer(), 9007199254740991)
    try expect_equal(min_safe_integer(), -9007199254740991)
    try expect_equal(max_int(), 9223372036854775807)
    try expect_equal(min_int() + 1, -9223372036854775807)
    try expect_true(near(sqrt2() * sqrt_half(), 1.0))
    try expect_true(near(ln10(), 2.302585092994046))
    try expect_true(near(log2e() * ln2(), 1.0))
    try expect_true(near(log10e() * ln10(), 1.0))
