// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	BigInt,
	WordDivision,
	add_with_carry,
	divide_wide,
	frexp,
	from_int,
	ieee_remainder,
	infinity,
	ldexp,
	max_float,
	max_int,
	min_float,
	min_int,
	modf,
	multiply_wide,
	nan,
	parse,
	remainder,
	remainder_wide,
	sign_bit,
	subtract_with_borrow from "@std/math/math.ms",
	expect_equal,
	expect_false,
	expect_ok,
	expect_some,
	expect_true from "@std/test/test.ms",
)

fn big_word(value: UInt64) BigInt:
	return parse(value.to_string_radix(10), 10).get()

test "carry and borrow operate on unsigned words and chain across limbs":
	largest: UInt64 := 18446744073709551615
	zero: UInt64 := 0
	one: UInt64 := 1
	low := add_with_carry(largest, one)
	expect_equal(low.sum, zero)?
	expect_true(low.carry)?

	high := add_with_carry(8, 9, low.carry)
	expect_equal(high.sum, 18)?
	expect_false(high.carry)?

	difference := subtract_with_borrow(zero, one)
	expect_equal(difference.difference, largest)?
	expect_true(difference.borrow)?

	high_difference := subtract_with_borrow(18, 9, difference.borrow)
	expect_equal(high_difference.difference, 8)?
	expect_false(high_difference.borrow)?
	expect_true(add_with_carry(largest, largest, true).carry)?
	expect_equal(add_with_carry(largest, zero, true).sum, zero)?
	expect_true(subtract_with_borrow(zero, largest, true).borrow)?
	expect_equal(subtract_with_borrow(zero, largest, true).difference, zero)?

test "word arithmetic matches exact BigInt references at all width boundaries":
	values: List[UInt64] := [
		0, 1, 4294967295, 4294967296, 9223372036854775808, 18446744073709551615
	]
	radix := from_int(1).shift_left(64)?

	for left in values:
		for right in values:
			a := big_word(left)
			b := big_word(right)

			for flag in [false, true]:
				extra := from_int(if flag: 1 else: 0)
				sum := add_with_carry(left, right, flag)
				exact_sum := a + b + extra
				expect_equal(big_word(sum.sum), exact_sum % radix)?
				expect_equal(sum.carry, exact_sum >= radix)?

				difference := subtract_with_borrow(left, right, flag)
				exact_difference := a - b - extra
				wrapped := if exact_difference.sign() < 0: exact_difference + radix else: exact_difference.clone()
				expect_equal(big_word(difference.difference), wrapped)?
				expect_equal(difference.borrow, exact_difference.sign() < 0)?

			product := multiply_wide(left, right)
			expect_equal(big_word(product.high) * radix + big_word(product.low), a * b)?

			for divisor in values:
				if divisor != 0:
					actual := remainder_wide(left, right, divisor)?
					expect_equal(big_word(actual), (a * radix + b) % big_word(divisor))?

			if left != 0:
				division := divide_wide(product.high, product.low, left)?
				expect_equal(division.quotient, right)?
				expect_equal(division.remainder, 0)?

test "wide division distinguishes invalid divisor and quotient overflow":
	largest: UInt64 := 18446744073709551615
	division := divide_wide(2, largest, 3)?
	expect_equal(division.quotient, largest)?
	expect_equal(division.remainder, 2)?

	invalid: WordDivision! := error(Error("number: invalid input", kind: "EINVAL"))
	overflow: WordDivision! := error(
		Error("number: value out of range", kind: "ERANGE")
	)
	expect_equal(divide_wide(0, 0, 0), invalid)?
	expect_equal(divide_wide(largest, largest, 0), invalid)?
	expect_equal(divide_wide(3, 0, 3), overflow)?
	expect_equal(divide_wide(largest, 0, largest), overflow)?
	expect_equal((remainder_wide(3, 5, 3)?), 2)?
	expect_equal((remainder_wide(largest, largest, largest)?), 0)?

	invalid_remainder: UInt64! := error(Error("number: invalid input", kind: "EINVAL"))
	expect_equal(remainder_wide(largest, largest, 0), invalid_remainder)?

test "binary float decomposition round trips normals subnormals and signed zero":
	for value in [
		0.0,
		-0.0,
		min_float,
		-min_float,
		1.0,
		-1.0,
		8.0,
		-8.0,
		1e-300,
		1e300,
		max_float,
	]:
		parts := frexp(value)
		rebuilt := ldexp(parts.fraction, parts.exponent)
		expect_equal(rebuilt, value)?
		expect_equal(sign_bit(rebuilt), sign_bit(value))?

		if value != 0.0:
			expect_true(parts.fraction.abs() >= 0.5)?
			expect_true(parts.fraction.abs() < 1.0)?
		else:
			expect_equal(parts.exponent, 0)?

	expect_equal(frexp(min_float).fraction, 0.5)?
	expect_equal(frexp(min_float).exponent, -1073)?
	expect_equal(frexp(max_float).exponent, 1024)?

	for value in [infinity, -infinity, nan]:
		parts := frexp(value)
		expect_equal(parts.exponent, 0)?

		if value.is_nan():
			expect_true(parts.fraction.is_nan())?
		else:
			expect_equal(parts.fraction, value)?

test "ldexp handles full Int exponents and IEEE boundary rounding":
	expect_equal(ldexp(0.5, 4), 8.0)?
	expect_equal(ldexp(0.5, -1073), min_float)?
	expect_equal(ldexp(0.5, -1074), 0.0)?
	expect_equal(ldexp(0.75, -1074), min_float)?
	expect_equal(ldexp(1.0, max_int), infinity)?
	expect_equal(ldexp(-1.0, max_int), -infinity)?
	expect_equal(ldexp(1.0, min_int), 0.0)?
	expect_true(sign_bit(ldexp(-1.0, min_int)))?

	for exponent in [min_int, max_int]:
		expect_true(sign_bit(ldexp(-0.0, exponent)))?
		expect_equal(ldexp(infinity, exponent), infinity)?
		expect_equal(ldexp(-infinity, exponent), -infinity)?
		expect_true(ldexp(nan, exponent).is_nan())?

test "float integer and fractional parts retain signs and special values":
	ordinary := modf(-2.75)
	expect_equal(ordinary.integer, -2.0)?
	expect_equal(ordinary.fraction, -0.75)?
	expect_true(sign_bit(modf(-0.5).integer))?
	expect_true(sign_bit(modf(-2.0).fraction))?
	expect_true(sign_bit(modf(-0.0).integer))?
	expect_true(sign_bit(modf(-0.0).fraction))?
	expect_equal(modf(infinity).integer, infinity)?
	expect_equal(modf(infinity).fraction, 0.0)?
	expect_equal(modf(-infinity).integer, -infinity)?
	expect_true(sign_bit(modf(-infinity).fraction))?
	expect_true(modf(nan).integer.is_nan())?
	expect_true(modf(nan).fraction.is_nan())?

	tiny := modf(-min_float)
	expect_true(sign_bit(tiny.integer))?
	expect_equal(tiny.fraction, -min_float)?

test "IEEE remainder uses nearest-even quotient without changing truncating remainder":
	expect_equal(remainder(5.0, 3.0), 2.0)?
	expect_equal(ieee_remainder(5.0, 3.0), -1.0)?
	expect_equal(ieee_remainder(5.0, 2.0), 1.0)?
	expect_equal(ieee_remainder(7.0, 2.0), -1.0)?
	expect_equal(ieee_remainder(-5.0, 2.0), -1.0)?
	expect_equal(ieee_remainder(5.0, -2.0), 1.0)?
	expect_true(sign_bit(ieee_remainder(-4.0, 2.0)))?
	expect_equal(ieee_remainder(min_float, min_float + min_float), min_float)?
	expect_equal(ieee_remainder(3.0, infinity), 3.0)?
	expect_true(sign_bit(ieee_remainder(-0.0, infinity)))?
	expect_true(ieee_remainder(infinity, 1.0).is_nan())?
	expect_true(ieee_remainder(1.0, 0.0).is_nan())?
	expect_true(ieee_remainder(nan, 1.0).is_nan())?
	expect_true(ieee_remainder(1.0, nan).is_nan())?

test "modular inverse distinguishes absence invalid modulus and the unit modulus":
	(
		from_int(271).inverse_mod(from_int(383))
		| expect_ok?
		| expect_some?
		| expect_equal(from_int(106))?
	)
	(
		from_int(-271).inverse_mod(
			from_int(383)
		) | expect_ok? | expect_some? | expect_equal(from_int(277))?
	)
	expect_true((from_int(6).inverse_mod(from_int(9))?).is_none())?
	expect_true((from_int(0).inverse_mod(from_int(2))?).is_none())?
	for number in [-5, 0, 5]:
		(
			from_int(number).inverse_mod(from_int(1))
			| expect_ok?
			| expect_some?
			| expect_equal(from_int(0))?
		)

	invalid: BigInt?! := error(Error("big integer: invalid input", kind: "EINVAL"))
	expect_equal(from_int(2).inverse_mod(from_int(0)), invalid)?
	expect_equal(from_int(2).inverse_mod(from_int(-7)), invalid)?

test "modular inverse scales to 4096 bits and retains canonical residues":
	one := from_int(1)

	for width in [64, 256, 1024, 4096]:
		modulus := one.shift_left(width)?
		base := modulus - one
		inverse := (base.inverse_mod(modulus)?) | expect_some?
		expect_equal(inverse, base)?
		expect_equal(base * inverse % modulus, one)?
		(
			base.negate().inverse_mod(modulus)
			| expect_ok?
			| expect_some?
			| expect_equal(one)?
		)
