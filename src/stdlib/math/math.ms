import (
	Data, panic from "@std/core.ms",
	random_bytes from "@std/random.ms",

	msrt_bits_bit_and,
	msrt_bits_bit_or,
	msrt_bits_bit_xor,
	msrt_bits_count_ones,
	msrt_bits_leading_zeros,
	msrt_bits_rotate_left,
	msrt_bits_rotate_right,
	msrt_bits_shift_left,
	msrt_bits_shift_right,
	msrt_bits_shift_right_unsigned,
	msrt_bits_trailing_zeros,
	msrt_bits_wrapping_add,
	msrt_bits_wrapping_multiply,
	msrt_bits_wrapping_subtract,
	msrt_numbers_parse_float,
	msrt_numbers_parse_int,
	msstd_bigint_abs,
	msstd_bigint_add,
	msstd_bigint_bit_and,
	msstd_bigint_bit_not,
	msstd_bigint_bit_or,
	msstd_bigint_bit_xor,
	msstd_bigint_compare,
	msstd_bigint_divide,
	msstd_bigint_from_int,
	msstd_bigint_gcd,
	msstd_bigint_inverse_mod,
	msstd_bigint_lcm,
	msstd_bigint_modulo,
	msstd_bigint_multiply,
	msstd_bigint_negate,
	msstd_bigint_parse,
	msstd_bigint_pow,
	msstd_bigint_pow_mod,
	msstd_bigint_quotient,
	msstd_bigint_remainder,
	msstd_bigint_shift_left,
	msstd_bigint_shift_right,
	msstd_bigint_sign,
	msstd_bigint_sqrt,
	msstd_bigint_subtract,
	msstd_bigint_to_float,
	msstd_bigint_to_int,
	msstd_bigint_to_string_radix,
	msstd_math_acos,
	msstd_math_acosh,
	msstd_math_add_with_carry,
	msstd_math_asin,
	msstd_math_asinh,
	msstd_math_atan,
	msstd_math_atan2,
	msstd_math_atanh,
	msstd_math_cbrt,
	msstd_math_ceil,
	msstd_math_copy_sign,
	msstd_math_cos,
	msstd_math_cosh,
	msstd_math_divide_wide,
	msstd_math_exp,
	msstd_math_exp2,
	msstd_math_expm1,
	msstd_math_floor,
	msstd_math_fma,
	msstd_math_frexp,
	msstd_math_hypot,
	msstd_math_ieee_remainder,
	msstd_math_is_integer,
	msstd_math_is_safe_integer,
	msstd_math_ldexp,
	msstd_math_log,
	msstd_math_log10,
	msstd_math_log1p,
	msstd_math_log2,
	msstd_math_modf,
	msstd_math_multiply_wide,
	msstd_math_next_after,
	msstd_math_pow,
	msstd_math_remainder,
	msstd_math_remainder_wide,
	msstd_math_round,
	msstd_math_round_to_even,
	msstd_math_sign_bit,
	msstd_math_sin,
	msstd_math_sinh,
	msstd_math_sqrt,
	msstd_math_subtract_with_borrow,
	msstd_math_tan,
	msstd_math_tanh,
	msstd_math_truncate from "@std/internal/math.ms",
)

/*
Floating-point and integer math: trigonometric, exponential, logarithmic and rounding functions on `Float`;
constants such as `pi` and `max_int`; `Int` helpers for bit manipulation, wrapping arithmetic and 128-bit word arithmetic;
text parsing with `parse_float` and `parse_int`; and `BigInt`, an arbitrary-precision integer, with `factorial` and `binomial`.
Float functions follow IEEE 754 rules for NaN, infinities and signed zero. For exact fractions see `@std/math/big.ms`,
for complex numbers `@std/math/complex.ms`, and for summary statistics `@std/math/statistics.ms`.
*/

// Returns the inverse cosine in radians.
export fn acos(value Float) Float {
	return msstd_math_acos(value)
}

// Returns the inverse sine in radians.
export fn asin(value Float) Float {
	return msstd_math_asin(value)
}

// Returns the inverse tangent in radians.
export fn atan(value Float) Float {
	return msstd_math_atan(value)
}

// Returns the angle in radians from the positive x axis to the point `(x, y)`, in -pi
// through pi. The signs of both arguments pick the quadrant, which is why `y` comes
// first.
export fn atan2(y, x Float) Float {
	return msstd_math_atan2(y, x)
}

// Rounds upward to the nearest whole number.
export fn ceil(value Float) Float {
	return msstd_math_ceil(value)
}

// Returns the cosine of an angle in radians.
export fn cos(value Float) Float {
	return msstd_math_cos(value)
}

// Returns the hyperbolic cosine.
export fn cosh(value Float) Float {
	return msstd_math_cosh(value)
}

// Euler's number, the base of natural logarithms.
export e Float := 2.718281828459045

// Returns e raised to `value`.
export fn exp(value Float) Float {
	return msstd_math_exp(value)
}

// Returns 2 raised to `value`; infinities and NaN follow IEEE floating-point rules.
export fn exp2(value Float) Float {
	return msstd_math_exp2(value)
}

// Rounds to the nearest integer, choosing the even integer at a tie; preserves signed
// zero, infinities, and NaN.
export fn round_to_even(value Float) Float {
	return msstd_math_round_to_even(value)
}

// Returns `value`'s magnitude with `sign`'s sign bit, including signed zero and NaN.
export fn copy_sign(value, sign Float) Float {
	return msstd_math_copy_sign(value, sign)
}

// Reports the sign bit, including for negative zero and negative NaN.
export fn sign_bit(value Float) Bool {
	return msstd_math_sign_bit(value)
}

// Returns the next representable Float from `value` toward `toward`, crossing
// subnormals, zero, and infinity exactly. Equal operands return `toward`, including its
// zero sign; either NaN operand gives NaN.
export fn next_after(value, toward Float) Float {
	return msstd_math_next_after(value, toward)
}

// Computes `left * right + addend` with one rounding, avoiding the intermediate
// product's rounding and overflow.
export fn fma(left, right, addend Float) Float {
	return msstd_math_fma(left, right, addend)
}

// A binary decomposition from `frexp`; `frexp(8.0)` has fraction 0.5 and exponent 4.
export type BinaryFloatParts {
	// The signed fraction; its magnitude is at least 0.5 and less than 1 for finite
	// nonzero inputs.
	fraction Float
	// The power of two; zero for zero, infinity, or NaN inputs.
	exponent Int
}

// The integer and fractional parts from `modf`; `modf(-2.75)` has integer -2.0 and
// fraction -0.75.
export type FloatParts {
	// The input truncated toward zero, retaining its sign, including zero and infinity.
	integer Float
	// The remainder after truncation, retaining the input's sign, including zero;
	// signed zero for infinity.
	fraction Float
}

// Decomposes `value` exactly as fraction * 2^exponent; use `ldexp` to reconstruct it.
// Zero, infinity and NaN give the unchanged fraction and exponent 0.
export fn frexp(value Float) BinaryFloatParts {
	return msstd_math_frexp(value)
}

// Multiplies `fraction` by 2^exponent with normal IEEE rounding, overflow and subnormal
// underflow. Accepts every Int exponent and preserves signed zero, infinity and NaN.
export fn ldexp(fraction Float, exponent Int) Float {
	return msstd_math_ldexp(fraction, exponent)
}

// Splits `value` into an integer truncated toward zero and its fractional remainder,
// both with the input's sign. Infinity gives itself and signed zero; NaN gives NaN for
// both parts.
export fn modf(value Float) FloatParts {
	return msstd_math_modf(value)
}

/*
Returns `left - n * right`, where n is the nearest integer to left/right, choosing an even n at a tie.
The result's magnitude is at most abs(right)/2; a zero result keeps left's sign.
A zero right, infinite left, or NaN input gives NaN; an infinite right returns finite left unchanged.
*/
export fn ieee_remainder(left, right Float) Float {
	return msstd_math_ieee_remainder(left, right)
}

// Rounds downward to the nearest whole number.
export fn floor(value Float) Float {
	return msstd_math_floor(value)
}

// Returns the length of the hypotenuse for sides `left` and `right`.
export fn hypot(left, right Float) Float {
	return msstd_math_hypot(left, right)
}

// Returns the natural logarithm.
export fn log(value Float) Float {
	return msstd_math_log(value)
}

// Returns the base-10 logarithm.
export fn log10(value Float) Float {
	return msstd_math_log10(value)
}

// Returns the base-2 logarithm.
export fn log2(value Float) Float {
	return msstd_math_log2(value)
}

// Returns the greater of two values, or `left` when they compare equal. Float orders
// NaN above every other value, so a NaN operand makes the result NaN.
export fn max[T Comparable](hold left, right T) & T {
	if right.compare(left) > 0 { return right }
	return left
}

// Returns the lesser of two values, or `left` when they compare equal. Float orders NaN
// above every other value, so `min` ignores a NaN operand unless both are NaN.
export fn min[T Comparable](hold left, right T) & T {
	if right.compare(left) < 0 { return right }
	return left
}

// Pi, the ratio of a circle's circumference to its diameter.
export pi Float := 3.141592653589793

// Returns `base` raised to `exponent`.
export fn pow(base, exponent Float) Float {
	return msstd_math_pow(base, exponent)
}

// Returns `base` raised to a nonnegative integer `exponent`, or null when the exponent
// is negative or the result does not fit in Int. Example: `pow_int(2, 10)` is 1024.
export fn pow_int(base, exponent Int) Int? {
	if exponent < 0 { return null }

	var result = 1
	var factor = base
	var left = exponent

	while left > 0 {
		if left % 2 == 1 {
			next_result := checked_multiply(result, factor)
			if next_result == null { return null }

			result = next_result
		}

		left /= 2

		if left > 0 {
			next_factor := checked_multiply(factor, factor)
			if next_factor == null { return null }

			factor = next_factor
		}
	}

	return result
}

// Multiplies two Ints, or returns null when the product does not fit in Int.
fn checked_multiply(left, right Int) Int? {
	if left == 0 or right == 0 { return 0 }

	product := wrapping_multiply(left, right)
	if left == min_int and right == -1 { return null }
	if right == min_int and left == -1 { return null }
	if product / right != left { return null }

	return product
}

// The floor quotient and the remainder of `divmod`.
export type DivMod {
	// The quotient rounded toward negative infinity.
	quotient Int
	// The remainder, which is zero or has the sign of the divisor.
	remainder Int
}

// Divides rounding toward negative infinity, like Python's `divmod`: the remainder
// has the divisor's sign and `quotient * divisor + remainder` is the dividend. Returns
// null for a zero divisor or the one overflowing case, `min_int` by -1.
// Example: `divmod(-7, 2)` is quotient -4, remainder 1.
export fn divmod(dividend, divisor Int) DivMod? {
	if divisor == 0 { return null }

	if divisor == -1 {
		if dividend == min_int { return null }
		return DivMod(quotient: -dividend, remainder: 0)
	}

	var quotient = dividend / divisor
	var remainder = dividend % divisor

	if remainder != 0 and (remainder < 0) != (divisor < 0) {
		quotient -= 1
		remainder += divisor
	}

	return DivMod(quotient: quotient, remainder: remainder)
}

// Returns the non-negative greatest common divisor; `gcd(0, 0)` is zero. Faults like
// `abs` when the result is 2^63, which Int cannot hold.
export fn gcd(left, right Int) Int {
	var a = left.abs()
	var b = right.abs()

	while b != 0 {
		next := a % b
		a = b
		b = next
	}

	return a
}

// Returns the non-negative least common multiple; zero when either value is zero.
// Faults like any Int overflow when the result does not fit.
export fn lcm(left, right Int) Int {
	if left == 0 or right == 0 { return 0 }
	return (left / gcd(left, right) * right).abs()
}

// Returns the floor of the square root, or null for a negative value.
// Example: `isqrt(17)` is 4.
export fn isqrt(value Int) Int? {
	if value < 0 { return null }
	if value < 2 { return value }

	var low = 1
	var high = value / 2 + 1
	if high > 3037000499 { high = 3037000499 }

	while low < high {
		mid := low + (high - low + 1) / 2

		if mid <= value / mid {
			low = mid
		} else {
			high = mid - 1
		}
	}

	return low
}

// Returns the floating-point remainder of `left / right` with the sign of `left`, like
// Int `%` (C `fmod`), not the IEEE round-to-nearest remainder: `remainder(5.0, 3.0)` is
// 2.0. A zero `right` or infinite `left` gives NaN; an infinite `right` returns `left`.
export fn remainder(left, right Float) Float {
	return msstd_math_remainder(left, right)
}

// Rounds to the nearest whole number, with ties toward positive infinity.
export fn round(value Float) Float {
	return msstd_math_round(value)
}

// Returns the sine of an angle in radians.
export fn sin(value Float) Float {
	return msstd_math_sin(value)
}

// Returns the hyperbolic sine.
export fn sinh(value Float) Float {
	return msstd_math_sinh(value)
}

// Returns the non-negative square root.
export fn sqrt(value Float) Float {
	return msstd_math_sqrt(value)
}

// Returns the tangent of an angle in radians.
export fn tan(value Float) Float {
	return msstd_math_tan(value)
}

// Returns the hyperbolic tangent.
export fn tanh(value Float) Float {
	return msstd_math_tanh(value)
}

// Truncates a value toward zero.
export fn truncate(value Float) Float {
	return msstd_math_truncate(value)
}

// Returns the inverse hyperbolic cosine; values below 1.0 give NaN.
export fn acosh(value Float) Float {
	return msstd_math_acosh(value)
}

// Returns the inverse hyperbolic sine.
export fn asinh(value Float) Float {
	return msstd_math_asinh(value)
}

// Returns the inverse hyperbolic tangent; magnitudes above 1.0 give NaN.
export fn atanh(value Float) Float {
	return msstd_math_atanh(value)
}

// Returns the real cube root, which is defined for negative values.
export fn cbrt(value Float) Float {
	return msstd_math_cbrt(value)
}

// Returns e raised to `value` minus one, accurate for values near zero.
export fn expm1(value Float) Float {
	return msstd_math_expm1(value)
}

// Returns the natural logarithm of one plus `value`, accurate for values near zero.
export fn log1p(value Float) Float {
	return msstd_math_log1p(value)
}

// Reports whether the value is finite and has no fractional part.
export fn is_integer(value Float) Bool {
	return msstd_math_is_integer(value)
}

// Reports whether the value is an integer within -(2^53 - 1) through 2^53 - 1, where
// Float represents integers exactly.
export fn is_safe_integer(value Float) Bool {
	return msstd_math_is_safe_integer(value)
}

// Positive infinity, the Float that exceeds every finite value; negate it for negative
// infinity.
export infinity Float := 1.0 / 0.0
// NaN, the Float that is not equal to itself under IEEE rules; use `is_nan()` to detect
// it.
export nan Float := 0.0 / 0.0
// The difference between 1.0 and the next larger Float.
export epsilon Float := 2.220446049250313e-16
// The largest finite Float.
export max_float Float := 1.7976931348623157e+308
// The smallest positive Float, a subnormal value.
export min_float Float := 5e-324
// The largest Int, 2^63 - 1.
export max_int Int := 9223372036854775807
// The smallest Int, -2^63.
export min_int Int := -9223372036854775807 - 1
// 2^53 - 1, the largest Int up to which every integer is exactly representable as a
// Float.
export max_safe_integer Int := 9007199254740991
// -(2^53 - 1), the smallest Int down to which every integer is exactly representable as
// a Float.
export min_safe_integer Int := -9007199254740991
// The natural logarithm of 2.
export ln2 Float := 0.6931471805599453
// The natural logarithm of 10.
export ln10 Float := 2.302585092994046
// The base-2 logarithm of e.
export log2e Float := 1.4426950408889634
// The base-10 logarithm of e.
export log10e Float := 0.43429448190325176
// The square root of 2.
export sqrt2 Float := 1.4142135623730951
// The square root of 1/2.
export sqrt_half Float := 0.7071067811865476

// Parses a decimal floating-point number using Manuscript's numeric syntax, plus `NaN`,
// `Infinity`, `+Infinity` and `-Infinity`.
export fn parse_float(text String) Float! {
	return msrt_numbers_parse_float(text)
}

// Parses an integer with an optional sign in a radix from 2 through 36; `_` separators
// and white space are not accepted. Radix 0 reads a `0x`, `0o` or `0b` prefix and
// otherwise uses 10. A bad digit is EBADMSG, an overflow ERANGE and an unsupported
// radix EINVAL.
export fn parse_int(text String, radix Int = 10) Int! {
	return msrt_numbers_parse_int(text, radix)
}

// Returns the bitwise AND of two integers.
export fn bit_and(left, right Int) Int {
	return msrt_bits_bit_and(left, right)
}

// Returns the bitwise OR of two integers.
export fn bit_or(left, right Int) Int {
	return msrt_bits_bit_or(left, right)
}

// Returns the bitwise exclusive OR of two integers.
export fn bit_xor(left, right Int) Int {
	return msrt_bits_bit_xor(left, right)
}

// Returns the bitwise complement, so every bit of the two's-complement value flips.
export fn bit_not(value Int) Int {
	return msrt_bits_bit_xor(value, -1)
}

// Shifts bits toward the high end, discarding bits shifted out. A `count` of 64 or more
// shifts every bit out and gives 0. A negative `count` faults.
export fn shift_left(value, count Int) Int {
	check_shift_count("shift_left", count)
	if count > 63 { return 0 }

	return msrt_bits_shift_left(value, count)
}

// Shifts bits toward the low end, filling with the sign bit. A `count` of 64 or more
// gives 0 for a value that is not negative and -1 for a negative one. A negative
// `count` faults.
export fn shift_right(value, count Int) Int {
	check_shift_count("shift_right", count)
	if count > 63 { return if value < 0 { - 1 } else { 0 } }

	return msrt_bits_shift_right(value, count)
}

// Shifts bits toward the low end, filling with zeros. A `count` of 64 or more gives 0.
// A negative `count` faults.
export fn shift_right_unsigned(value, count Int) Int {
	check_shift_count("shift_right_unsigned", count)
	if count > 63 { return 0 }

	return msrt_bits_shift_right_unsigned(value, count)
}

fn check_shift_count(operation String, count Int) Void {
	if count < 0 {
		panic(f"{operation}: count must not be negative, found {count}")
	}
}

// Rotates the 64-bit pattern toward the high end; any `count` is reduced modulo 64.
export fn rotate_left(value, count Int) Int {
	return msrt_bits_rotate_left(value, count)
}

// Rotates the 64-bit pattern toward the low end; any `count` is reduced modulo 64.
export fn rotate_right(value, count Int) Int {
	return msrt_bits_rotate_right(value, count)
}

// Counts the set bits in the 64-bit pattern.
export fn count_ones(value Int) Int {
	return msrt_bits_count_ones(value)
}

// Counts the zero bits above the highest set bit; zero has 64.
export fn leading_zeros(value Int) Int {
	return msrt_bits_leading_zeros(value)
}

// Counts the zero bits below the lowest set bit; zero has 64.
export fn trailing_zeros(value Int) Int {
	return msrt_bits_trailing_zeros(value)
}

// Reverses all 64 bits of the two's-complement pattern; reversing twice returns
// `value`.
export fn reverse_bits(value Int) Int {
	x := reverse_bytes(value)
	nibbles := msrt_bits_bit_or(
		msrt_bits_bit_and(
			msrt_bits_shift_right_unsigned(x, 4),
			0x0F0F0F0F0F0F0F0F,
		),
		msrt_bits_shift_left(msrt_bits_bit_and(x, 0x0F0F0F0F0F0F0F0F), 4),
	)
	pairs := msrt_bits_bit_or(
		msrt_bits_bit_and(
			msrt_bits_shift_right_unsigned(nibbles, 2),
			0x3333333333333333,
		),
		msrt_bits_shift_left(msrt_bits_bit_and(nibbles, 0x3333333333333333), 2),
	)
	return msrt_bits_bit_or(
		msrt_bits_bit_and(
			msrt_bits_shift_right_unsigned(pairs, 1),
			0x5555555555555555,
		),
		msrt_bits_shift_left(msrt_bits_bit_and(pairs, 0x5555555555555555), 1),
	)
}

// Reverses the eight bytes of the 64-bit pattern, keeping bit order within each byte;
// independent of host byte order.
export fn reverse_bytes(value Int) Int {
	bytes := msrt_bits_bit_or(
		msrt_bits_bit_and(
			msrt_bits_shift_right_unsigned(value, 8),
			0x00FF00FF00FF00FF,
		),
		msrt_bits_shift_left(msrt_bits_bit_and(value, 0x00FF00FF00FF00FF), 8),
	)
	halves := msrt_bits_bit_or(
		msrt_bits_bit_and(
			msrt_bits_shift_right_unsigned(bytes, 16),
			0x0000FFFF0000FFFF,
		),
		msrt_bits_shift_left(msrt_bits_bit_and(bytes, 0x0000FFFF0000FFFF), 16),
	)
	return msrt_bits_rotate_left(halves, 32)
}

// The wrapped sum and output carry from `add_with_carry`; `add_with_carry(1, 2).sum` is
// 3.
export type WordSum {
	// The low 64 bits of left + right + input carry.
	sum UInt64
	// True when the unsigned mathematical sum exceeds UInt64's range.
	carry Bool
}

// The wrapped difference and output borrow from `subtract_with_borrow`;
// `subtract_with_borrow(5, 2).difference` is 3.
export type WordDifference {
	// The low 64 bits of left - right - input borrow.
	difference UInt64
	// True when the unsigned mathematical difference is negative.
	borrow Bool
}

// An exact unsigned 128-bit product from `multiply_wide`; `multiply_wide(2, 3)` has
// high 0 and low 6.
export type WideProduct {
	// The upper 64 bits of the product.
	high UInt64
	// The lower 64 bits of the product.
	low UInt64
}

// A quotient and remainder from `divide_wide`; `divide_wide(0, 7, 3)` gives quotient 2
// and remainder 1.
export type WordDivision {
	// The unsigned quotient, guaranteed to fit in 64 bits.
	quotient UInt64
	// The unsigned remainder, smaller than the divisor.
	remainder UInt64
}

// Adds two unsigned 64-bit words and an optional input `carry`; returns the wrapped sum
// and output carry.
export fn add_with_carry(left, right UInt64, carry Bool = false) WordSum {
	return msstd_math_add_with_carry(left, right, carry)
}

// Subtracts `right` and an optional input `borrow` from `left`; returns the wrapped
// difference and output borrow.
export fn subtract_with_borrow(left, right UInt64, borrow Bool = false) WordDifference {
	return msstd_math_subtract_with_borrow(left, right, borrow)
}

// Multiplies two unsigned 64-bit words exactly, returning the upper and lower 64-bit
// words.
export fn multiply_wide(left, right UInt64) WideProduct {
	return msstd_math_multiply_wide(left, right)
}

// Divides the unsigned 128-bit value high * 2^64 + low by divisor, returning a 64-bit
// quotient and remainder. A zero divisor returns EINVAL; otherwise high >= divisor
// returns ERANGE because the quotient cannot fit.
export fn divide_wide(high, low, divisor UInt64) WordDivision! {
	return msstd_math_divide_wide(high, low, divisor)
}

// Returns the remainder of the unsigned 128-bit value high * 2^64 + low divided by
// divisor. A zero divisor returns EINVAL; any nonzero divisor is valid, even when the
// quotient would not fit in 64 bits.
export fn remainder_wide(high, low, divisor UInt64) UInt64! {
	return msstd_math_remainder_wide(high, low, divisor)
}

// Adds with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_add(left, right Int) Int {
	return msrt_bits_wrapping_add(left, right)
}

// Subtracts with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_subtract(left, right Int) Int {
	return msrt_bits_wrapping_subtract(left, right)
}

// Multiplies with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_multiply(left, right Int) Int {
	return msrt_bits_wrapping_multiply(left, right)
}

/*
An arbitrary-precision signed integer. Use the operators + - * / % and unary - for arithmetic and < <= > >= == != for comparison.
Both operands must be BigInt (convert an Int with `big_int_of_int`), and / or % by zero is a fault.
The named methods below perform the same operations. `divide` and `remainder` return a Result for callers that want an error value instead of a fault.
*/
// ms: data
export extern type BigInt

// Returns an independent copy, so `var acc = base.clone()` starts an accumulator.
fn BigInt.clone() move BigInt {
	return msstd_bigint_add(self, msstd_bigint_from_int(0))
}

// Returns the exact sum; arbitrary precision means it cannot overflow.
fn BigInt.add(other BigInt) BigInt {
	return msstd_bigint_add(self, other)
}

// Returns the exact difference `self - other`; it cannot overflow.
fn BigInt.subtract(other BigInt) BigInt {
	return msstd_bigint_subtract(self, other)
}

// Returns the exact product; it cannot overflow, though very large operands take
// proportionally longer.
fn BigInt.multiply(other BigInt) BigInt {
	return msstd_bigint_multiply(self, other)
}

// Returns the non-negative greatest common divisor; gcd(0, 0) is zero.
// Example: `big_int_of_int(-12).gcd(big_int_of_int(18))` is `big_int_of_int(6)`.
fn BigInt.gcd(other BigInt) BigInt {
	return msstd_bigint_gcd(self, other)
}

// Returns the non-negative least common multiple, or zero when either operand is
// zero.
fn BigInt.lcm(other BigInt) BigInt {
	return msstd_bigint_lcm(self, other)
}

// Returns the floor of the exact integer square root; a negative receiver returns
// EINVAL.
fn BigInt.sqrt() BigInt! {
	return msstd_bigint_sqrt(self)
}

/*
Returns `self` raised to a non-negative BigInt exponent modulo a positive modulus, in 0 through modulus - 1.
A negative exponent or non-positive modulus returns EINVAL. A zero exponent gives 1 modulo modulus, including 0^0.
Reduces during exponentiation instead of constructing the full power. Variable-time; unsuitable for secret exponents.
*/
fn BigInt.pow_mod(exponent, modulus BigInt) BigInt! {
	return msstd_bigint_pow_mod(self, exponent, modulus)
}

// Returns the multiplicative inverse modulo a positive modulus, in 0 through
// modulus - 1; a non-positive modulus returns EINVAL. No inverse gives ok(null);
// modulus 1 gives zero. Variable-time; unsuitable for secret operands.
fn BigInt.inverse_mod(modulus BigInt) BigInt?! {
	if modulus.sign() <= 0 {
		return error(Error("big integer: invalid input", kind: "EINVAL"))
	}
	return ok(msstd_bigint_inverse_mod(self, modulus))
}

// Returns the quotient truncated toward zero, so -7 divided by 2 is -3.
// A zero divisor returns EINVAL.
fn BigInt.divide(other BigInt) BigInt! {
	return msstd_bigint_divide(self, other)
}

// Returns the remainder whose sign follows the dividend, so -7 remainder 2 is -1.
// A zero divisor returns EINVAL.
fn BigInt.remainder(other BigInt) BigInt! {
	return msstd_bigint_remainder(self, other)
}

// Returns -1 when this value is less than `other`, 0 when equal, and 1 when
// greater.
fn BigInt.compare(other BigInt) Int {
	return msstd_bigint_compare(self, other)
}

// Returns the lesser of this value and `other`, or this value when they compare
// equal.
fn hold BigInt.min(other BigInt) & BigInt {
	if other.compare(self) < 0 { return other }
	return self
}

// Returns the greater of this value and `other`, or this value when they compare
// equal.
fn hold BigInt.max(other BigInt) & BigInt {
	if other.compare(self) > 0 { return other }
	return self
}

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault.
fn hold BigInt.clamp(hold low, high BigInt) & BigInt {
	if low.compare(high) > 0 {
		panic("clamp: low must not be greater than high")
	}
	if self.compare(
		low
	) < 0 { return low }
	if self.compare(high) > 0 { return high }

	return self
}

// Returns the bitwise AND using infinite-width two's-complement semantics, so
// negative operands behave as if sign-extended.
fn BigInt.bit_and(other BigInt) BigInt {
	return msstd_bigint_bit_and(self, other)
}

// Returns the bitwise OR using infinite-width two's-complement semantics, so
// negative operands behave as if sign-extended.
fn BigInt.bit_or(other BigInt) BigInt {
	return msstd_bigint_bit_or(self, other)
}

// Returns the bitwise XOR using infinite-width two's-complement semantics, so
// negative operands behave as if sign-extended.
fn BigInt.bit_xor(other BigInt) BigInt {
	return msstd_bigint_bit_xor(self, other)
}

// Returns the bitwise complement using infinite-width two's-complement semantics,
// so `bit_not(x)` equals `-x - 1`.
fn BigInt.bit_not() BigInt {
	return msstd_bigint_bit_not(self)
}

// Returns the value with its sign flipped.
fn BigInt.negate() BigInt {
	return msstd_bigint_negate(self)
}

// Returns the absolute value, which is never negative.
fn BigInt.abs() BigInt {
	return msstd_bigint_abs(self)
}

// Returns -1, 0 or 1 as the value is negative, zero or positive.
fn BigInt.sign() Int {
	return msstd_bigint_sign(self)
}

// Returns `self` raised to a nonnegative `exponent`. A negative exponent returns
// EINVAL, and a result above 16777216 bits returns EOVERFLOW.
fn BigInt.pow(exponent Int) BigInt! {
	return msstd_bigint_pow(self, exponent)
}

// Shifts left by `count` bits, multiplying by two to that power. A negative count
// returns EINVAL, and a result above 16777216 bits returns EOVERFLOW.
fn BigInt.shift_left(count Int) BigInt! {
	return msstd_bigint_shift_left(self, count)
}

// Shifts right by `count` bits with floor semantics for negatives, so -5 shifted by
// 1 is -3. A negative count returns EINVAL.
fn BigInt.shift_right(count Int) BigInt! {
	return msstd_bigint_shift_right(self, count)
}

// Converts to the nearest Float, or returns null when the magnitude exceeds the
// Float range.
fn BigInt.to_float() Float? {
	value := msstd_bigint_to_float(self)
	if value.is_finite() { return value }

	return null
}

// Returns the value as an Int, or null when it is outside Int's range.
fn BigInt.to_int() Int? {
	return msstd_bigint_to_int(self)
}

// Formats the value in a radix from 2 through 36 using lowercase digits and a
// leading `-` for negatives, or null when the radix is outside 2 through 36.
fn BigInt.to_string_radix(radix Int) String? {
	if radix < 2 or radix > 36 { return null }
	return msstd_bigint_to_string_radix(self, radix)
}

// Formats the value in base 16 using lowercase digits and a leading `-` for
// negatives; it cannot fail.
fn BigInt.to_hex() String {
	return msstd_bigint_to_string_radix(self, 16)
}

// Formats the value in base 2 with a leading `-` for negatives; it cannot fail.
fn BigInt.to_binary() String {
	return msstd_bigint_to_string_radix(self, 2)
}

/*
Reports whether this value is probably prime: trial division by the primes below 100, then Miller-Rabin
with the first `rounds` primes as bases (at most 25, the primes below 100). The default 13 rounds is exact below 3.3e24.
Above that bound, `rounds` more bases are drawn from operating-system entropy, so a composite passes with odds at most 4^-rounds
even when it was built to fool fixed bases; an entropy failure is a fault.
Values below 2, including negatives, are not prime. A `rounds` below 1 is a programming fault.
*/
fn BigInt.is_probable_prime(rounds Int = 13) Bool {
	if rounds < 1 {
		panic("is_probable_prime: rounds must be at least 1")
	}
	return bigint_probable_prime(self, rounds)
}

/*
Returns a square root of this value modulo the odd prime `modulus`, in 0 through modulus - 1, or null when the value is not a square there.
The other root is `modulus` minus the result. A modulus below 3, an even modulus, or one that is not prime returns EINVAL.
A composite modulus is not reliably detected: the call may return EINVAL, null, or a valid root, so only a prime modulus gives a trustworthy null.
*/
fn BigInt.mod_sqrt(modulus BigInt) BigInt?! {
	return bigint_mod_sqrt(self, modulus)
}

// Converts a machine-sized integer without loss.
export fn big_int_of_int(value Int) BigInt {
	return msstd_bigint_from_int(value)
}

// Parses an integer with an optional sign in a radix from 2 through 36; `_` separators
// and white space are not accepted. Pass `max_digits` to bound the work on untrusted
// text. A bad digit or empty text is EBADMSG, more digits than `max_digits` is
// EOVERFLOW, and an unsupported radix is EINVAL.
export fn parse_big_int(text String, radix Int, max_digits Int?) BigInt! {
	return msstd_bigint_parse(text, radix, max_digits)
}

// Returns n! for a non-negative n; a negative n returns EINVAL. Work and result size
// grow quickly with n.
export fn factorial(n Int) BigInt! {
	if n < 0 { return error(Error("big integer: invalid input", kind: "EINVAL")) }
	if n < 2 { return ok(msstd_bigint_from_int(1)) }

	return ok(range_product(2, n))
}

// The product of low through high inclusive, split in halves so each multiplication
// pairs similar sizes.
fn range_product(low, high Int) BigInt {
	if high - low < 16 {
		var product = msstd_bigint_from_int(low)
		for factor in low + 1..high + 1 {
			product *= msstd_bigint_from_int(factor)
		}
		return product
	}

	middle := low + (high - low) / 2
	return range_product(low, middle) * range_product(middle + 1, high)
}

// Returns the binomial coefficient "n choose k", which is 0 when k exceeds n; a
// negative n or k returns EINVAL.
export fn binomial(n, k Int) BigInt! {
	if n < 0 or k < 0 {
		return error(Error("big integer: invalid input", kind: "EINVAL"))
	}
	if k > n { return ok(msstd_bigint_from_int(0)) }

	choose := if n - k < k { n - k } else { k }
	var result = msstd_bigint_from_int(1)
	for step in 0..choose {
		result = (
			result
			* msstd_bigint_from_int(n - step)
			/ msstd_bigint_from_int(step + 1)
		)
	}
	return ok(result)
}

fn bigint_zero() BigInt {
	return msstd_bigint_from_int(0)
}

fn bigint_is_even(value BigInt) Bool {
	return (value % msstd_bigint_from_int(2)).sign() == 0
}

fn bigint_probable_prime(n BigInt, rounds Int) Bool {
	if n.compare(msstd_bigint_from_int(2)) < 0 { return false }

	primes := [
		2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73,
		79, 83, 89, 97
	]

	for p in primes {
		divisor := msstd_bigint_from_int(p)
		if n.compare(divisor) == 0 { return true }
		if (n % divisor).sign() == 0 { return false }
	}

	minus_one := n - msstd_bigint_from_int(1)
	var odd_part = minus_one.clone()
	var twos = 0

	while bigint_is_even(odd_part) {
		odd_part = odd_part.shift_right(1).get_or(bigint_zero())
		twos += 1
	}

	fixed := min(rounds, primes.length())
	for index in 0..fixed {
		if not bigint_strong_probable(
			n,
			msstd_bigint_from_int(primes[index]),
			odd_part,
			twos,
		) {
			return false
		}
	}

	// The first 13 prime bases decide every value below this bound exactly. Above it,
	// fixed bases can be fooled by a composite built for them, so the requested rounds
	// are repeated with secret random bases.
	bound := msstd_bigint_parse("3317044064679887385961981", 10, null).get_or(
		bigint_zero()
	)
	if n.compare(bound) < 0 { return true }

	for _round in 0..rounds {
		if not bigint_strong_probable(n, bigint_random_base(n), odd_part, twos) {
			return false
		}
	}
	return true
}

// One Miller-Rabin round: whether `n` (odd, with n - 1 = odd_part * 2^twos) is a strong
// probable prime to `base`.
fn bigint_strong_probable(n, base, odd_part BigInt, twos Int) Bool {
	one := msstd_bigint_from_int(1)
	minus_one := n - one
	var x = base.pow_mod(odd_part, n).get_or(bigint_zero())
	if x.compare(
		one
	) == 0 or x.compare(minus_one) == 0 { return true }

	for _step in 1..twos {
		x = x * x % n
		if x.compare(minus_one) == 0 { return true }
	}

	return false
}

// A base drawn from operating-system entropy in 2 through n - 2, for n above the
// deterministic bound.
fn bigint_random_base(n BigInt) BigInt {
	size := n.to_hex().length() / 2 + 8
	data := random_bytes(size)
	if data.is_error() {
		panic("is_probable_prime: the operating system entropy source failed")
	}

	var value = bigint_zero()
	base := msstd_bigint_from_int(256)
	for byte in data.get().values() {
		value = value * base + msstd_bigint_from_int(byte.to_int())
	}

	span := n - msstd_bigint_from_int(3)
	return value % span + msstd_bigint_from_int(2)
}

fn bigint_square_times(value BigInt, times Int, modulus BigInt) BigInt {
	var result = value % modulus
	for _round in 0..times {
		result = result * result % modulus
	}
	return result
}

fn bigint_mod_sqrt(value, modulus BigInt) BigInt?! {
	one := msstd_bigint_from_int(1)
	two := msstd_bigint_from_int(2)
	if modulus.compare(msstd_bigint_from_int(3)) < 0 or bigint_is_even(modulus) {
		return error(Error("big integer: invalid input", kind: "EINVAL"))
	}

	var target = value % modulus
	if target.sign() < 0 {
		target += modulus
	}

	absent BigInt? := null
	if target.sign() == 0 { return ok(bigint_zero()) }

	minus_one := modulus - one
	half := minus_one / two
	if target.pow_mod(half, modulus).get_or(bigint_zero()).compare(one) != 0 {
		return ok(absent)
	}

	var root = bigint_zero()

	if (modulus % msstd_bigint_from_int(4)).compare(msstd_bigint_from_int(3)) == 0 {
		root = target.pow_mod(
			(modulus + one) / msstd_bigint_from_int(4),
			modulus,
		).get_or(bigint_zero())
	} else {
		var odd_part = minus_one.clone()
		var twos = 0

		while bigint_is_even(odd_part) {
			odd_part /= two
			twos += 1
		}

		var non_residue = two.clone()

		while true {
			criterion := non_residue.pow_mod(half, modulus)?
			if criterion.compare(minus_one) == 0 { break }

			// A prime gives only +1 or -1 here; any other value proves compositeness.
			if criterion.compare(one) != 0 {
				return error(Error("big integer: invalid input", kind: "EINVAL"))
			}

			non_residue += one
		}

		var m = twos
		var c = non_residue.pow_mod(odd_part, modulus).get_or(bigint_zero())
		var t = target.pow_mod(odd_part, modulus).get_or(bigint_zero())
		root = target.pow_mod((odd_part + one) / two, modulus).get_or(bigint_zero())

		while t.compare(one) != 0 {
			var i = 0
			var probe = t.clone()

			while probe.compare(one) != 0 and i < m {
				probe = probe * probe % modulus
				i += 1
			}

			if i == 0 or i >= m {
				return error(Error("big integer: invalid input", kind: "EINVAL"))
			}

			b := bigint_square_times(c, m - i - 1, modulus)
			m = i
			c = b * b % modulus
			t = t * c % modulus
			root = root * b % modulus
		}
	}

	if (root * root % modulus).compare(target) != 0 {
		return error(Error("big integer: invalid input", kind: "EINVAL"))
	}

	return ok(root)
}
