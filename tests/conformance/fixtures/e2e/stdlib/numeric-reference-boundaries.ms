// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	BigRat,
	big_float_of_float,
	big_float_of_rat,
	parse_rat,
	rat,
	rat_of_big_int,
	rat_of_float,
	rat_of_int from "@std/math/big.ms",
	BigInt,
	add_with_carry,
	big_int_of_int,
	bit_and,
	bit_not,
	bit_or,
	bit_xor,
	ceil,
	copy_sign,
	count_ones,
	divide_wide,
	floor,
	fma,
	frexp,
	ieee_remainder,
	is_integer,
	ldexp,
	leading_zeros,
	max_int,
	min_int,
	modf,
	multiply_wide,
	next_after,
	parse_int,
	remainder,
	remainder_wide,
	rotate_left,
	rotate_right,
	round,
	round_to_even,
	shift_left,
	shift_right,
	shift_right_unsigned,
	sqrt,
	subtract_with_borrow,
	trailing_zeros,
	truncate,
	wrapping_add,
	wrapping_multiply,
	wrapping_subtract from "@std/math/math.ms",
	finite_float_boundaries,
	float_boundaries,
	int_boundaries from "@std/test/boundary.ms",
	expect_equal, expect_error, expect_some, expect_true, fail from "@std/test/test.ms",
)

// The two's-complement 64-bit wrap of an exact integer.
fn wrap64(value BigInt) BigInt!:
	modulus := big_int_of_int(1).shift_left(64)?
	var reduced = value.remainder(modulus)?
	if reduced.sign() < 0:
		reduced += modulus

	half := big_int_of_int(1).shift_left(63)?
	if reduced.compare(half) >= 0:
		reduced -= modulus
	return ok(reduced)

fn same_float(actual Float, expected Float) Bool:
	if actual.is_nan() or expected.is_nan():
		return actual.is_nan() and expected.is_nan()
	return (
		actual == expected and 1.0 / actual == 1.0 / expected
		or actual == expected and actual != 0.0
	)

test "wrapping arithmetic matches exact arithmetic reduced mod 2^64":
	for a in int_boundaries():
		for b in int_boundaries():
			sum := wrap64(big_int_of_int(a) + big_int_of_int(b))?
			difference := wrap64(big_int_of_int(a) - big_int_of_int(b))?
			product := wrap64(big_int_of_int(a) * big_int_of_int(b))?
			expect_equal(big_int_of_int(wrapping_add(a, b)), sum)?
			expect_equal(big_int_of_int(wrapping_subtract(a, b)), difference)?
			expect_equal(big_int_of_int(wrapping_multiply(a, b)), product)?

fn big_of_word(word UInt64) BigInt:
	small := word.to_int()
	if small != null: return big_int_of_int(small)

	low := (word - 9223372036854775808).to_int() or 0
	return big_int_of_int(low) + big_int_of_int(max_int) + big_int_of_int(1)

test "multiply_wide matches the exact 128-bit product":
	words List[UInt64] := [
		0, 1, 2, 4294967295, 4294967296, 9223372036854775807, 9223372036854775808,
		18446744073709551615
	]

	for a in words:
		for b in words:
			exact := big_of_word(a) * big_of_word(b)
			parts := multiply_wide(a, b)
			shifted := big_of_word(parts.high).shift_left(64)?
			expect_equal(shifted + big_of_word(parts.low), exact)?

test "rounding functions agree with exact rationals":
	for x in finite_float_boundaries():
		exact := rat_of_float(x) or rat_of_int(0)
		expect_equal(
			(rat_of_float(floor(x)) or rat_of_int(7)).numerator(),
			exact.floor(),
		)?
		expect_equal((rat_of_float(ceil(x)) or rat_of_int(7)).numerator(), exact.ceil())?
		expect_equal(
			(rat_of_float(truncate(x)) or rat_of_int(7)).numerator(),
			exact.truncate(),
		)?

		// `round` sends ties toward positive infinity, unlike `BigRat.round`, which sends them away from zero.
		half := rat(big_int_of_int(1), big_int_of_int(2))?
		expect_equal(
			(rat_of_float(round(x)) or rat_of_int(7)).numerator(),
			exact.add(half).floor(),
		)?

test "nonfinite inputs pass through the rounding functions":
	for x in [infinity_value(), -infinity_value()]:
		expect_true(same_float(floor(x), x))?
		expect_true(same_float(ceil(x), x))?
		expect_true(same_float(round(x), x))?
		expect_true(same_float(truncate(x), x))?
		expect_true(same_float(round_to_even(x), x))?

	not_a_number := infinity_value() - infinity_value()
	expect_true(floor(not_a_number).is_nan())?
	expect_true(ceil(not_a_number).is_nan())?
	expect_true(round(not_a_number).is_nan())?
	expect_true(truncate(not_a_number).is_nan())?

fn infinity_value() Float:
	return 1.0 / 0.0

test "modf splits exactly":
	for x in finite_float_boundaries():
		parts := modf(x)
		whole := rat_of_float(parts.integer) or rat_of_int(7)
		fraction := rat_of_float(parts.fraction) or rat_of_int(7)
		expect_equal(whole.add(fraction), rat_of_float(x) or rat_of_int(7))?
		expect_equal(whole, rat_of_float(truncate(x)) or rat_of_int(7))?

test "frexp and ldexp round-trip every finite value":
	for x in finite_float_boundaries():
		parts := frexp(x)
		expect_true(same_float(ldexp(parts.fraction, parts.exponent), x))?

		if x != 0.0:
			magnitude := parts.fraction.abs()
			expect_true(magnitude >= 0.5 and magnitude < 1.0)?

test "next_after moves by exactly one representable step":
	for x in finite_float_boundaries():
		up := next_after(x, infinity_value())
		down := next_after(x, -infinity_value())
		expect_true(up > x)?
		expect_true(down < x)?

		exact := rat_of_float(x) or rat_of_int(0)
		exact_up := rat_of_float(up)
		exact_down := rat_of_float(down)
		u := exact_up
		if u != null:
			expect_equal(u.compare(exact), 1)?

		d := exact_down
		if d != null:
			expect_equal(d.compare(exact), -1)?

test "to_fixed matches the exact decimal expansion":
	for x in finite_float_boundaries():
		if x.abs() < 1e21:
			exact := rat_of_float(x) or rat_of_int(0)

			for digits in [0, 1, 2, 5, 20]:
				expected := exact.to_fixed(digits)?
				actual := x.to_fixed(digits)

				// A negative value that rounds to zero prints as `-0`, as in C; compare
				// it without the sign.
				unsigned := if actual.starts_with("-") and not expected.starts_with("-"): actual.view(
					1,
					actual.length(),
				).clone() else: actual
				expect_equal(unsigned, expected)?

test "truncate_to_int is exact inside the Int range and none outside it":
	for x in float_boundaries():
		result := x.truncate_to_int()

		if not x.is_finite():
			expect_equal(result, null)?
		else:
			exact := (rat_of_float(x) or rat_of_int(0)).truncate()
			value := exact.to_int()

			if value != null:
				expect_equal(result, value)?
			else:
				expect_equal(result, null)?

test "fma and sqrt are correctly rounded":
	for x in finite_float_boundaries():
		if x >= 0.0:
			reference := big_float_of_float(x, 200)

			if reference != null:
				if root := reference.sqrt():
					rounded := big_float_of_rat(root.to_rat(), 53).to_float()
					expect_equal(sqrt(x), rounded or 0.0)?

	for a in [1.0, 0.1, 1e308, -1e308, 1e-308, 5e-324]:
		for b in [1.0, 3.0, 1e10, -0.1, 1e-10]:
			for c in [0.0, 1.0, -1e308, 5e-324]:
				exact := (rat_of_float(a) or rat_of_int(0)).multiply(
					rat_of_float(b) or rat_of_int(0)
				).add(rat_of_float(c) or rat_of_int(0))
				nearest := exact.to_float()
				if nearest != null:
					expect_true(same_float(fma(a, b, c), nearest) or nearest == 0.0)?

fn word_boundaries() List[UInt64]:
	return [
		0, 1, 2, 4294967295, 4294967296, 9223372036854775807, 9223372036854775808,
		18446744073709551614, 18446744073709551615
	]

fn two_pow(count Int) BigInt:
	return big_int_of_int(1).shift_left(count).get_or(big_int_of_int(0))

test "add_with_carry and subtract_with_borrow match exact words":
	modulus := two_pow(64)

	for a in word_boundaries():
		for b in word_boundaries():
			for carry in [false, true]:
				extra := if carry: big_int_of_int(1) else: big_int_of_int(0)
				exact := big_of_word(a) + big_of_word(b) + extra
				sum := add_with_carry(a, b, carry)
				rebuilt := (
					big_of_word(sum.sum)
					+ (
						if sum
						.carry: modulus
						.clone() else: big_int_of_int(0)
					)
				)
				expect_equal(rebuilt, exact)?

				diff := subtract_with_borrow(a, b, carry)
				exact_diff := big_of_word(a) - big_of_word(b) - extra
				rebuilt_diff := (
					big_of_word(diff.difference)
					- (
						if diff
						.borrow: modulus
						.clone() else: big_int_of_int(0)
					)
				)
				expect_equal(rebuilt_diff, exact_diff)?

test "divide_wide and remainder_wide match exact division":
	for high in word_boundaries():
		for low in word_boundaries():
			for divisor in word_boundaries():
				numerator := ((big_of_word(high).shift_left(64)?) + big_of_word(low))

				if divisor == 0:
					_failure := expect_error(divide_wide(high, low, divisor))?
					_failure2 := expect_error(remainder_wide(high, low, divisor))?
				else:
					divisor_big := big_of_word(divisor)
					remainder := remainder_wide(high, low, divisor)?
					expect_equal(
						big_of_word(remainder),
						numerator.remainder(divisor_big)?,
					)?

					if high >= divisor:
						_failure := expect_error(divide_wide(high, low, divisor))?
					else:
						result := divide_wide(high, low, divisor)?
						expect_equal(
							big_of_word(result.quotient),
							numerator.divide(divisor_big)?,
						)?
						expect_equal(
							big_of_word(result.remainder),
							numerator.remainder(
								divisor_big
							)?,
						)?

test "bit operations match BigInt two's complement":
	for a in int_boundaries():
		for b in int_boundaries():
			expect_equal(
				big_int_of_int(bit_and(a, b)),
				big_int_of_int(a).bit_and(big_int_of_int(b)),
			)?
			expect_equal(
				big_int_of_int(bit_or(a, b)),
				big_int_of_int(a).bit_or(big_int_of_int(b)),
			)?
			expect_equal(
				big_int_of_int(bit_xor(a, b)),
				big_int_of_int(a).bit_xor(big_int_of_int(b)),
			)?

		expect_equal(big_int_of_int(bit_not(a)), big_int_of_int(a).bit_not())?

test "shifts and rotations agree with exact arithmetic at every count":
	for a in int_boundaries():
		for count in [0, 1, 2, 31, 32, 33, 62, 63]:
			shifted := wrap64(big_int_of_int(a).shift_left(count)?)?
			expect_equal(big_int_of_int(shift_left(a, count)), shifted)?
			expect_equal(
				big_int_of_int(shift_right(a, count)),
				big_int_of_int(a).shift_right(count)?,
			)?

			rotated := rotate_left(rotate_right(a, count), count)
			expect_equal(rotated, a)?

			word := if a < 0: big_int_of_int(a) + two_pow(64) else: big_int_of_int(a)
			logical := word.shift_right(count)?
			expect_equal(
				big_int_of_int(shift_right_unsigned(a, count)),
				wrap64(logical)?,
			)?

test "bit counts match the binary expansion":
	for a in int_boundaries():
		word := if a < 0: big_int_of_int(a) + two_pow(64) else: big_int_of_int(a)
		digits := word.to_binary()
		var ones = 0
		for c in digits.chars():
			if c == "1":
				ones += 1
		expect_equal(count_ones(a), ones)?

		expected_leading := if a == 0: 64 else: 64 - digits.length()
		expect_equal(leading_zeros(a), expected_leading)?

		trailing := digits.length() - ((digits.last_index_of("1") or 0) + 1)
		expect_equal(trailing_zeros(a), if a == 0: 64 else: trailing)?

test "integer conversions respect each target range":
	for a in int_boundaries():
		expect_equal(a.to_int8() != null, a >= -128 and a <= 127)?
		expect_equal(a.to_int16() != null, a >= -32768 and a <= 32767)?
		expect_equal(a.to_int32() != null, a >= -2147483648 and a <= 2147483647)?
		expect_equal(a.to_uint8() != null, a >= 0 and a <= 255)?
		expect_equal(a.to_uint16() != null, a >= 0 and a <= 65535)?
		expect_equal(a.to_uint32() != null, a >= 0 and a <= 4294967295)?
		expect_equal(a.to_uint64() != null, a >= 0)?

test "radix text and parsing round-trip every boundary":
	for a in int_boundaries():
		for radix in [2, 8, 10, 16, 36]:
			text := expect_some(a.to_string_radix(radix))?
			expect_equal(big_int_of_int(a).to_string_radix(radix), text)?
			expect_equal(parse_int(text, radix)?, a)?

		expect_equal(f"{a}".parse_int(), a)?

test "BigInt agrees with Int on operations that cannot overflow":
	for a in int_boundaries():
		for b in int_boundaries():
			expect_equal(big_int_of_int(a).compare(big_int_of_int(b)), a.compare(b))?

			// Int division faults on min_int / -1; BigInt has the exact quotient.
			if b != 0 and not (a == min_int and b == -1):
				expect_equal(
					big_int_of_int(a).divide(big_int_of_int(b))?,
					big_int_of_int(a / b),
				)?

test "Float text round-trips exactly":
	for x in float_boundaries():
		back := x.to_string().parse_float()

		if x.is_nan():
			expect_true((back or 0.0).is_nan())?
		else:
			expect_true(same_float(back or 1.5, x))?

		for digits in [1, 17, 100]:
			text := x.to_precision(digits)
			if x.is_finite() and digits >= 17:
				expect_true(same_float(text.parse_float() or 1.5, x))?

test "parse_float rounds like the exact rational at the range edges":
	cases := [
		"1.7976931348623157e308", "1.7976931348623159e308", "1.797693134862315807e308",
		"2.4703282292062327e-324", "2.4703282292062328e-324", "5e-324",
		"4.9406564584124654e-324", "2.2250738585072011e-308", "9007199254740993",
		"9007199254740993.0000000000000000000001", "0.30000000000000004", "1e-400",
		"-1e-400", "1e400"
	]

	for text in cases:
		exact := parse_rat(text)?
		parsed := text.parse_float()
		nearest := exact.to_float()

		if nearest != null:
			expect_true(
				same_float(
					parsed or 1.5,
					nearest,
				) or nearest == 0.0 and (parsed or 1.5) == 0.0
			)?
		else:
			expect_true((parsed == null) or not (parsed).is_finite())?

test "BigRat and BigFloat arithmetic is exact or correctly rounded on Float boundaries":
	for x in finite_float_boundaries():
		for y in finite_float_boundaries():
			a := rat_of_float(x) or rat_of_int(0)
			b := rat_of_float(y) or rat_of_int(0)
			expect_equal(a.add(b).subtract(b), a)?
			expect_equal(a.multiply(b).compare(b.multiply(a)), 0)?
			if y != 0.0:
				expect_equal((a.divide(b)?).multiply(b), a)?

			sum := x + y

			if sum.is_finite():
				nearest := a.add(b).to_float()
				if nearest != null:
					expect_true(
						same_float(
							sum,
							nearest,
						) or nearest == 0.0 and sum == 0.0
					)?

			product := x * y

			if product.is_finite():
				nearest := a.multiply(b).to_float()
				if nearest != null:
					expect_true(
						same_float(
							product,
							nearest,
						) or nearest == 0.0 and product == 0.0
					)?

test "ieee_remainder and remainder follow their definitions":
	for x in finite_float_boundaries():
		for y in finite_float_boundaries():
			if y != 0.0 and x.abs() < 1e300 and y.abs() > 1e-300:
				a := rat_of_float(x) or rat_of_int(0)
				b := rat_of_float(y) or rat_of_int(0)
				quotient := a.divide(b)?
				r := ieee_remainder(x, y)
				exact := rat_of_float(r) or rat_of_int(7)

				// r = x - n*y for an integer n, with |r| <= |y|/2.
				n := a.subtract(exact).divide(b)?
				expect_true(n.is_integer())?

				half := rat(big_int_of_int(1), big_int_of_int(2))?
				expect_true(exact.abs().compare(b.abs().multiply(half)) <= 0)?

				t := rat_of_float(remainder(x, y)) or rat_of_int(7)
				expected_t := a.subtract(
					b.multiply(rat_of_big_int(quotient.truncate()))
				)
				expect_equal(t, expected_t)?

test "conversions between Int and Float are exact where the type allows":
	for a in int_boundaries():
		f := a.to_float()
		exact := rat_of_int(a)
		nearest := exact.to_float() or 0.0
		expect_true(same_float(f, nearest))?
		expect_equal(big_int_of_int(a).to_float() or 0.0, nearest)?

test "Float32 conversion rounds once and rejects only overflow":
	for x in float_boundaries():
		narrowed := x.to_float32()

		if x.is_finite() and x.abs() > 3.4028235677973366e38:
			expect_true(narrowed == null)?
		else:
			expect_true(narrowed != null)?

test "BigInt shifts powers and bounds at the limits":
	one := big_int_of_int(1)

	for count in [0, 1, 63, 64, 65, 1000]:
		shifted := one.shift_left(count)?
		expect_equal(shifted.shift_right(count)?, one.clone())?
		expect_equal(big_int_of_int(-1).shift_right(count)?, big_int_of_int(-1))?

	negative_shift := one.shift_left(-1)
	_e := expect_error(negative_shift)?
	too_big := one.shift_left(16777217)
	_e2 := expect_error(too_big)?
	min := big_int_of_int(min_int)
	expect_equal(min.negate().to_int(), null)?
	expect_equal(min.abs().to_int(), null)?
	expect_equal(min.to_int(), min_int)?

test "extreme exponents do not wrap or hang":
	expect_true(same_float(ldexp(1.0, max_int), 1.0 / 0.0))?
	expect_true(same_float(ldexp(1.0, min_int), 0.0))?
	expect_true(same_float(ldexp(-1.0, min_int), -0.0))?
	expect_true(same_float(ldexp(5e-324, 1074), 1.0))?
	expect_true(same_float(ldexp(1.0, -1074), 5e-324))?
	expect_true(same_float(ldexp(1.0, -1075), 0.0))?
	expect_true(same_float(ldexp(1.5, -1075), 5e-324))?

fn ten_pow(exponent Int) BigRat:
	var power = rat_of_int(1)
	var step = 0

	while step < (if exponent < 0: -exponent else: exponent):
		power = power.multiply(rat_of_int(10))
		step += 1

	if exponent < 0: return power.invert().get_or(rat_of_int(1))

	return power

test "to_exponential matches the exact decimal expansion":
	for x in finite_float_boundaries():
		if x != 0.0:
			exact := (rat_of_float(x) or rat_of_int(0)).abs()
			var exponent = 0
			while exact.compare(ten_pow(exponent + 1)) >= 0:
				exponent += 1
			while exact.compare(ten_pow(exponent)) < 0:
				exponent -= 1

			for digits in [0, 3, 16, 17, 20]:
				var mantissa = exact.multiply(ten_pow(-exponent)).to_fixed(digits)?
				var shown = exponent

				if mantissa.starts_with("10"):
					shown = exponent + 1
					mantissa = exact.multiply(ten_pow(-shown)).to_fixed(digits)?

				sign := if x < 0.0: "-" else: ""
				exponent_sign := if shown < 0: "-" else: "+"
				magnitude := if shown < 0: -shown else: shown
				expect_equal(
					x.to_exponential(digits),
					f"{sign}{mantissa}e{exponent_sign}{magnitude}",
				)?

test "Decimal arithmetic matches BigInt while the result fits 34 digits":
	for a in int_boundaries():
		for b in int_boundaries():
			x := a.to_decimal()
			y := b.to_decimal()
			expect_equal(
				(x + y).to_fixed(0),
				Result.ok(
					(
						big_int_of_int(a)
						+ big_int_of_int(b)
					).to_string()
				),
			)?
			expect_equal(
				(x - y).to_fixed(0),
				Result.ok(
					(
						big_int_of_int(a)
						- big_int_of_int(b)
					).to_string()
				),
			)?
			expect_equal(x.compare(y), a.compare(b))?

			product := big_int_of_int(a) * big_int_of_int(b)
			if product.abs().to_string().length() <= 34:
				expect_equal((x * y).to_fixed(0), Result.ok(product.to_string()))?
