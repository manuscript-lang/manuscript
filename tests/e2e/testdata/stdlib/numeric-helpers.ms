import (
	BigInt,
	bit_xor,
	copy_sign,
	exp2,
	fma,
	from_int,
	infinity,
	max_float,
	min_float,
	nan,
	next_after,
	parse,
	reverse_bits,
	reverse_bytes,
	round_to_even,
	shift_left,
	sign_bit,
	wrapping_multiply from "@std/math/math.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

test "bit and byte reversal map every position in a 64-bit pattern":
	expect_equal(reverse_bits(0), 0)?
	expect_equal(reverse_bytes(-1), -1)?

	for position in 0..64:
		value := shift_left(1, position)
		expect_equal(reverse_bits(value), shift_left(1, 63 - position))?
		expect_equal(
			reverse_bytes(value),
			shift_left(1, (7 - position / 8) * 8 + position % 8),
		)?

	var value = 81985529216486895

	for unused in 0..256:
		expect_equal(reverse_bits(reverse_bits(value)), value)?
		expect_equal(reverse_bytes(reverse_bytes(value)), value)?
		value = bit_xor(
			wrapping_multiply(value, 6364136223846793005),
			-7046029254386353131,
		)

test "base-two exponentiation includes underflow overflow and special values":
	expect_equal(exp2(0.0), 1.0)?
	expect_equal(exp2(10.0), 1024.0)?
	expect_equal(exp2(-10.0), 0.0009765625)?
	expect_equal(exp2(-1074.0), min_float)?
	expect_equal(exp2(-1075.0), 0.0)?
	expect_equal(exp2(1024.0), infinity)?
	expect_equal(exp2(-infinity), 0.0)?
	expect_true(exp2(nan).is_nan())?

test "ties-even rounding and sign helpers preserve IEEE sign distinctions":
	values := [0.5, 1.5, 2.5, -0.5, -1.5, -2.5]
	expected := [0.0, 2.0, 2.0, 0.0, -2.0, -2.0]
	for i in 0..values.length():
		expect_equal(round_to_even(values.get(i)), expected.get(i))?
	expect_true(sign_bit(round_to_even(-0.5)))?
	expect_true(sign_bit(round_to_even(-0.0)))?
	expect_false(sign_bit(round_to_even(0.5)))?
	expect_equal(round_to_even(infinity), infinity)?
	expect_equal(round_to_even(-infinity), -infinity)?
	expect_true(round_to_even(nan).is_nan())?
	expect_equal(copy_sign(-3.0, 1.0), 3.0)?
	expect_equal(copy_sign(3.0, -1.0), -3.0)?
	expect_true(sign_bit(copy_sign(0.0, -1.0)))?
	expect_false(sign_bit(copy_sign(-0.0, 1.0)))?

	negative_nan := copy_sign(nan, -1.0)
	expect_true(negative_nan.is_nan())?
	expect_true(sign_bit(negative_nan))?
	expect_equal(copy_sign(infinity, negative_nan), -infinity)?

test "adjacent floats cross signed zeros subnormals and infinities exactly":
	expect_equal(next_after(1.0, 2.0), 1.0000000000000002)?
	expect_equal(next_after(1.0, 0.0), 0.9999999999999999)?
	expect_equal(next_after(0.0, 1.0), min_float)?
	expect_equal(next_after(0.0, -1.0), -min_float)?
	expect_true(sign_bit(next_after(0.0, -0.0)))?
	expect_false(sign_bit(next_after(-0.0, 0.0)))?
	expect_false(sign_bit(next_after(min_float, -1.0)))?
	expect_true(sign_bit(next_after(-min_float, 1.0)))?
	expect_equal(next_after(max_float, infinity), infinity)?
	expect_equal(next_after(infinity, 0.0), max_float)?
	expect_equal(next_after(-max_float, -infinity), -infinity)?
	expect_equal(next_after(-infinity, 0.0), -max_float)?
	expect_true(next_after(nan, 0.0).is_nan())?
	expect_true(next_after(0.0, nan).is_nan())?

test "fused multiply-add rounds once and avoids intermediate overflow":
	left := 1.0000000074505806
	right := 0.9999999925494194
	expect_equal(left * right - 1.0, 0.0)?
	expect_equal(fma(left, right, -1.0), -5.551115123125783e-17)?
	expect_equal(fma(max_float, 2.0, -max_float), max_float)?
	expect_true(fma(0.0, infinity, 1.0).is_nan())?
	expect_true(fma(nan, 1.0, 0.0).is_nan())?

test "big integer gcd and lcm normalize signs and zero":
	for left in [-12, 0, 12]:
		for right in [-18, 0, 18]:
			a := from_int(left)
			b := from_int(right)
			common := a.gcd(b)
			multiple := a.lcm(b)
			expect_equal(common, b.gcd(a))?
			expect_equal(multiple, b.lcm(a))?
			expect_equal(common * multiple, (a * b).abs())?
			expect_false(common.sign() < 0)?
			expect_false(multiple.sign() < 0)?

	expect_equal(from_int(-12).gcd(from_int(18)), from_int(6))?
	expect_equal(from_int(-12).lcm(from_int(18)), from_int(36))?
	expect_equal(from_int(0).gcd(from_int(0)), from_int(0))?
	expect_equal(from_int(0).lcm(from_int(0)), from_int(0))?

test "big integer square root is exact and rejects negative input":
	for number in [0, 1, 2, 3, 4, 15, 16, 17, 9223372036854775807]:
		value := from_int(number)
		root := value.sqrt()?
		expect_true(root * root <= value)?

		above := root + from_int(1)
		expect_true(above * above > value)?

	invalid: BigInt! := error(Error("big integer: invalid input", kind: "EINVAL"))
	expect_equal(from_int(-1).sqrt(), invalid)?

test "modular exponentiation normalizes results and validates its domain":
	expect_equal((from_int(2).pow_mod(from_int(10), from_int(1000))?), from_int(24))?
	expect_equal((from_int(-2).pow_mod(from_int(3), from_int(5))?), from_int(2))?
	expect_equal((from_int(-2).pow_mod(from_int(4), from_int(5))?), from_int(1))?
	expect_equal((from_int(0).pow_mod(from_int(0), from_int(7))?), from_int(1))?
	expect_equal((from_int(0).pow_mod(from_int(0), from_int(1))?), from_int(0))?

	invalid: BigInt! := error(Error("big integer: invalid input", kind: "EINVAL"))
	expect_equal(from_int(2).pow_mod(from_int(-1), from_int(7)), invalid)?
	expect_equal(from_int(2).pow_mod(from_int(3), from_int(0)), invalid)?
	expect_equal(from_int(2).pow_mod(from_int(3), from_int(-7)), invalid)?

test "big integer helpers scale from machine words to 4096-bit values":
	one := from_int(1)

	for width in [64, 256, 1024, 4096]:
		factor := (one.shift_left(width)?) + one
		a := factor * from_int(35)
		b := factor * from_int(77)
		expect_equal(a.gcd(b), factor * from_int(7))?
		expect_equal(a.lcm(b), factor * from_int(385))?

		square := factor * factor
		expect_equal((square.sqrt()?), factor)?
		expect_equal(((square - one).sqrt()?), factor - one)?

		modulus := (one.shift_left(width)?) - one
		expect_equal((from_int(2).pow_mod(from_int(width), modulus)?), one)?

	exponent := parse("184467440737095516160000000000000000000000", 10)?
	expect_equal((from_int(2).pow_mod(exponent, from_int(7))?), from_int(2))?

test "modular exponentiation matches exact large odd and even modulus reference vectors":
	base := parse("-123456789012345678901234567891", 10)?
	exponent := from_int(12345)
	odd := parse("10000000000000000000000000000000000000007", 10)?
	even := parse("340282366920938463463374607431768211456", 10)?
	odd_result := parse("4339799581317112657124184116489215648661", 10)?
	even_result := parse("223193219010250399600239597668322418573", 10)?
	expect_equal((base.pow_mod(exponent, odd)?), odd_result)?
	expect_equal((base.pow_mod(exponent, even)?), even_result)?
