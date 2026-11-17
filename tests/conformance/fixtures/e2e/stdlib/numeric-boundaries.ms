// conform: tags=testing,tier-io
// conform: phase=test
import (
	Decimal from "@std/math/decimal.ms",
	BigInt, from_int from "@std/math/math.ms",
	expect_equal, expect_false from "@std/test/test.ms",
	nanoseconds from "@std/time.ms",
)

test "integer division retains signed boundary and remainder rules":
	minimum := -9223372036854775808
	expect_false(minimum / 1 != minimum or minimum % -1 != 0)?
	expect_false(-7 / 2 != -3 or - 7 % 3 != -1)?
	expect_false(7 / -2 != -3 or 7 % -3 != 1)?
	expect_false(0 / minimum != 0 or 1 / minimum != 0)?
	expect_equal(1d / -1d, -1d)?
	expect_false((1.0 / 0.0).is_finite() or not (0.0 / 0.0).is_nan())?

	invalid: BigInt! := error(Error("big integer: invalid input", kind: "EINVAL"))
	expect_equal(from_int(1).divide(from_int(0)), invalid)?
	expect_equal(from_int(1).remainder(from_int(0)), invalid)?

test "duration arithmetic retains full signed nanosecond range":
	minimum := nanoseconds(-9223372036854775808)
	maximum := nanoseconds(9223372036854775807)
	expect_false(
		(
			minimum.divide(1) != minimum
			or maximum.divide(-1) != nanoseconds((-9223372036854775807))
		)
	)?
	expect_equal(minimum.divide(-9223372036854775808), nanoseconds(1))?
	expect_false(
		(
			minimum.multiply(0) != nanoseconds(0)
			or nanoseconds(0).multiply(-9223372036854775808) != nanoseconds(
				0
			)
		)
	)?
	expect_false(
		(
			minimum.multiply(1) != minimum
			or maximum.multiply(-1) != nanoseconds((-9223372036854775807))
		)
	)?
	expect_equal(
		nanoseconds(-1).multiply(9223372036854775807),
		nanoseconds((-9223372036854775807)),
	)?
	expect_false(
		(
			minimum.add(maximum) != nanoseconds(-1)
			or maximum.subtract(maximum) != nanoseconds(0)
		)
	)?

test "duration safe addition subtraction negation and unit edges":
	minimum := nanoseconds(-9223372036854775808)
	maximum := nanoseconds(9223372036854775807)
	expect_false(
		(
			minimum.add(nanoseconds(0)) != minimum
			or maximum.subtract(nanoseconds(0)) != maximum
		)
	)?
	expect_false(
		(
			minimum + maximum != nanoseconds(-1)
			or minimum - nanoseconds(-1) != nanoseconds(
				(-9223372036854775807)
			)
		)
	)?
	expect_false(
		(
			nanoseconds(-9223372036854775807).negate() != maximum
			or nanoseconds((-9223372036854775807)).abs() != maximum
		)
	)?
	expect_false(
		(
			nanoseconds(0).negate() != nanoseconds(0)
			or nanoseconds(0).abs() != nanoseconds(0)
		)
	)?
	expect_equal((9223372036854).milliseconds().to_nanoseconds(), 9223372036854000000)?
	expect_equal(
		(-9223372036854).milliseconds().to_nanoseconds(),
		(-9223372036854000000),
	)?
	expect_false(
		(
			(9223372036).seconds().to_nanoseconds() != 9223372036000000000
			or (
				-9223372036
			).seconds().to_nanoseconds() != -9223372036000000000
		)
	)?
	expect_false(
		(
			(153722867).minutes().to_nanoseconds() != 9223372020000000000
			or (
				-153722867
			).minutes().to_nanoseconds() != -9223372020000000000
		)
	)?

test "sized numbers widen to Int and Float with to_int and to_float":
	a: Int8 := -100
	b: Int16 := -7
	c: Int32 := 70000
	d: Int64 := 9
	f: Float32 := 0.5
	total: Int := a.to_int() + b.to_int() + c.to_int() + d.to_int()
	expect_equal(total, 69902)?
	expect_equal(f.to_float(), 0.5)?
