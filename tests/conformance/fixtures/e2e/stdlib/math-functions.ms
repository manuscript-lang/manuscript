// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	acos,
	acosh,
	asin,
	asinh,
	atan,
	atan2,
	atanh,
	cbrt,
	cosh,
	e,
	epsilon,
	exp,
	expm1,
	infinity,
	is_integer,
	is_safe_integer,
	ln10,
	ln2,
	log10,
	log10e,
	log1p,
	log2e,
	max,
	max_float,
	max_int,
	max_safe_integer,
	min,
	min_float,
	min_int,
	min_safe_integer,
	nan,
	pi,
	remainder,
	sinh,
	sqrt2,
	sqrt_half,
	tan,
	tanh from "@std/math/math.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

fn near(actual: Float, expected: Float) Bool:
	return (actual - expected).abs() < 0.000000001

test "inverse trigonometric functions return radians":
	expect_false(not near(acos(1.0), 0.0))?
	expect_false(not near(acos(0.0), pi / 2.0))?
	expect_false(not near(asin(1.0), pi / 2.0))?
	expect_false(not near(asin(0.0), 0.0))?
	expect_false(not near(atan(1.0), pi / 4.0))?
	expect_false(not near(atan2(1.0, 1.0), pi / 4.0))?
	expect_false(not near(atan2(1.0, -1.0), 3.0 * pi / 4.0))?

test "tangent hyperbolic exponential and logarithm functions":
	expect_false(not near(tan(0.0), 0.0))?
	expect_false(not near(tan(pi / 4.0), 1.0))?
	expect_false(not near(sinh(0.0), 0.0))?
	expect_false(not near(cosh(0.0), 1.0))?
	expect_false(not near(tanh(0.0), 0.0))?
	expect_false(not near(tanh(1.0), 0.7615941559557649))?
	expect_false(not near(exp(0.0), 1.0))?
	expect_false(not near(exp(1.0), e))?
	expect_false(not near(log10(1000.0), 3.0))?

test "float remainder takes the sign of the dividend":
	expect_equal(remainder(5.0, 3.0), 2.0)?
	expect_equal(remainder(-5.0, 3.0), -2.0)?
	expect_equal(remainder(7.0, 2.0), 1.0)?
	expect_false(not remainder(5.0, 0.0).is_nan())?

type Ranked:
	rank: Int

fn Ranked.compare(other: Ranked) Int:
	if self.rank < other.rank: return -9223372036854775808
	if self.rank > other.rank: return 9223372036854775807

	return 0

test "extrema use comparator signs without negating Int minimum":
	low := Ranked(1)
	high := Ranked(2)
	expect_equal(min(high.clone(), low.clone()).rank, 1)?
	expect_equal(max(low.clone(), high.clone()).rank, 2)?

	for values in [[high.clone(), low.clone()], [low.clone(), high.clone()]]:
		expect_equal(values.min().get().rank, 1)?
		expect_equal(values.max().get().rank, 2)?

	values := [high.clone(), low.clone(), Ranked(1), Ranked(2)]
	var minimum = values.min().get().clone()
	var maximum = values.max().get().clone()
	minimum.rank = 0
	maximum.rank = 3
	expect_false(values[1].rank != 1 or values[2].rank != 1)?
	expect_false(values[0].rank != 2 or values[3].rank != 2)?

test "inverse hyperbolic cube root and precision helpers":
	expect_true(near(acosh(1.0), 0.0))?
	expect_true(near(asinh(0.0), 0.0))?
	expect_true(near(atanh(0.0), 0.0))?
	expect_true(atanh(1.0) == infinity)?
	expect_true(acosh(0.5).is_nan())?
	expect_true(near(cbrt(27.0), 3.0))?
	expect_true(near(cbrt(-8.0), -2.0))?
	expect_true(near(expm1(0.0), 0.0))?
	expect_true(near(log1p(0.0), 0.0))?
	expect_true(near(log1p(1.0), ln2))?

test "sign and integer predicates":
	expect_equal((-3.5).sign(), -1.0)?
	expect_equal(2.0.sign(), 1.0)?
	expect_true(nan.sign().is_nan())?
	expect_equal((-9).sign(), -1)?
	expect_equal(0.sign(), 0)?
	expect_equal(12.sign(), 1)?
	expect_true(is_integer(4.0))?
	expect_false(is_integer(4.5))?
	expect_false(is_integer(infinity))?
	expect_false(is_integer(nan))?
	expect_true(is_safe_integer(9007199254740991.0))?
	expect_false(is_safe_integer(9007199254740992.0))?
	expect_equal(0.1.to_float32().get(0.0).to_float64() == 0.1, false)?
	expect_equal(1e300.to_float32(), none)?

test "numeric limits and constants match IEEE and JavaScript":
	expect_true(infinity > max_float)?
	expect_true(nan.is_nan())?
	expect_equal(1.0 + epsilon > 1.0, true)?
	expect_equal(1.0 + epsilon / 2.0 > 1.0, false)?
	expect_true(min_float > 0.0)?
	expect_equal(max_safe_integer, 9007199254740991)?
	expect_equal(min_safe_integer, -9007199254740991)?
	expect_equal(max_int, 9223372036854775807)?
	expect_equal(min_int + 1, -9223372036854775807)?
	expect_true(near(sqrt2 * sqrt_half, 1.0))?
	expect_true(near(ln10, 2.302585092994046))?
	expect_true(near(log2e * ln2, 1.0))?
	expect_true(near(log10e * ln10, 1.0))?
