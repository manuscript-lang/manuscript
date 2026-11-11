// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Decimal from "@std/math/decimal.ms",
	ceil,
	cos,
	floor,
	hypot,
	log2,
	max,
	min,
	pi,
	pow,
	round,
	sin,
	sqrt,
	truncate from "@std/math/math.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

test "decimal arithmetic is exact and conversion truncates":
	expect_equal(0.1d + 0.2d, 0.3d)?
	expect_equal(1.00d, 1d)?
	expect_equal((-1.9d).truncate_to_int(), -1)?
	expect_equal(2d.to_float(), 2.0)?
	expect_equal(1e400d.to_float(), none)?
	expect_equal(123.to_decimal(), 123d)?

test "decimal integer conversions normalize boundary values":
	minimum: Int := -9223372036854775808
	maximum: Int := 9223372036854775807
	unsigned: UInt64 := 18446744073709551615
	power: UInt64 := 10000000000000000000
	expect_equal(minimum.to_decimal(), -9223372036854775808d)?
	expect_equal(maximum.to_decimal(), 9223372036854775807d)?
	expect_equal(unsigned.to_decimal(), 18446744073709551615d)?
	expect_equal(power.to_decimal(), 1e19d)?
	expect_equal((-1000000000000000000).to_decimal(), -1e18d)?
	expect_equal(0.to_decimal(), 0d)?

test "decimal negation keeps full precision and exponent":
	maximum := 9.999999999999999999999999999999999e6144d
	minimum := 1e-6176d
	expect_equal(-maximum, -9.999999999999999999999999999999999e6144d)?
	expect_equal(-(-maximum), maximum)?
	expect_equal(-minimum, -1e-6176d)?
	expect_equal(-(-minimum), minimum)?
	expect_equal(-0d, 0d)?

test "math rounding signs and exact identities":
	expect_false((-2.5).abs() != 2.5 or (-3).abs() != 3)?
	expect_false(ceil(-1.5) != -1.0 or floor(-1.5) != -2.0)?
	expect_false(round(2.5) != 3.0 or truncate(-1.9) != -1.0)?
	expect_false(sqrt(9.0) != 3.0 or hypot(3.0, 4.0) != 5.0)?
	expect_false(pow(2.0, 3.0) != 8.0 or log2(8.0) != 3.0)?
	expect_false(min(2.0, 3.0) != 2.0 or max(2.0, 3.0) != 3.0)?
	expect_false((sin(0.0) != 0.0 or cos(0.0) != 1.0 or pi < 3.14))?
	expect_false(not sqrt(-1.0).is_nan())?
