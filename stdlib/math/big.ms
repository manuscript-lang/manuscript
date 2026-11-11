import (
	panic from "@std/core.ms",
	BigInt, frexp, from_int, ldexp, max, parse, parse_int from "@std/math/math.ms",
)

/*
An exact fraction of two arbitrary-precision integers, always in lowest terms with a positive denominator,
so two equal values compare equal with `==`. Arithmetic uses named methods and never rounds.
Build values with `rat`, `rat_of_int`, `rat_of_big_int`, `rat_of_float` or `parse_rat`.
Example: `(parse_rat("1/3")?).add(parse_rat("1/6")?).format()` is `"1/2"`.
*/
export opaque type BigRat:
	// The signed numerator in lowest terms.
	num: BigInt
	// The positive denominator in lowest terms.
	den: BigInt

impl BigRat:
	// Returns the numerator, which carries the sign.
	fn numerator() BigInt:
		return self.num

	// Returns the positive denominator.
	fn denominator() BigInt:
		return self.den

	// Returns an independent copy.
	fn clone() BigRat:
		return BigRat(num: self.num.clone(), den: self.den.clone())

	// Returns the exact sum.
	fn add(other: BigRat) BigRat:
		return reduced(
			self.num * other.den + other.num * self.den,
			self.den * other.den,
		)

	// Returns the exact difference.
	fn subtract(other: BigRat) BigRat:
		return reduced(
			self.num * other.den - other.num * self.den,
			self.den * other.den,
		)

	// Returns the exact product.
	fn multiply(other: BigRat) BigRat:
		return reduced(self.num * other.num, self.den * other.den)

	// Returns the exact quotient; a zero divisor returns EINVAL.
	fn divide(other: BigRat) BigRat!:
		return rat(self.num * other.den, self.den * other.num)

	// Returns `1 / self`; zero returns EINVAL.
	fn invert() BigRat!:
		return rat(self.den.clone(), self.num.clone())

	// Returns the same magnitude with the opposite sign; zero stays zero.
	fn negate() BigRat:
		return BigRat(num: -self.num, den: self.den.clone())

	// Returns the absolute value.
	fn abs() BigRat:
		return BigRat(num: self.num.abs(), den: self.den.clone())

	// Returns -1, 0 or 1 by sign.
	fn sign() Int:
		return self.num.sign()

	// Returns true when the denominator is 1.
	fn is_integer() Bool:
		return self.den.compare(big(1)) == 0

	// Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
	fn compare(other: BigRat) Int:
		return (self.num * other.den).compare(other.num * self.den)

	// Returns the lesser value, or this value when they compare equal.
	fn min(other: BigRat) BigRat:
		if other.compare(self) < 0: return other.clone()
		return self.clone()

	// Returns the greater value, or this value when they compare equal.
	fn max(other: BigRat) BigRat:
		if other.compare(self) > 0: return other.clone()
		return self.clone()

	// Returns the exact power. A negative exponent returns the reciprocal power, so
	// zero with a negative exponent returns EINVAL. A numerator or denominator power
	// above 16777216 bits returns EOVERFLOW.
	fn pow(exponent: Int) BigRat!:
		// `abs` faults on the minimum Int, so take its magnitude as `max + 1` powers.
		extra := exponent == -9223372036854775807 - 1
		count := if extra: 9223372036854775807 else: exponent.abs()
		var top = self.num.pow(count)?
		var bottom = self.den.pow(count)?

		if extra:
			top *= self.num
			bottom *= self.den

		if exponent >= 0: return ok(BigRat(num: top, den: bottom))

		return rat(bottom, top)

	// Returns the largest integer not greater than this value.
	fn floor() BigInt:
		return floor_div(self.num, self.den)

	// Returns the smallest integer not less than this value.
	fn ceil() BigInt:
		return -floor_div(-self.num, self.den)

	// Discards the fraction toward zero.
	fn truncate() BigInt:
		return self.num / self.den

	// Rounds to the nearest integer; an exact tie rounds away from zero.
	fn round() BigInt:
		twice := self.num.abs() * big(2) + self.den
		magnitude := twice / (self.den * big(2))
		if self.num.sign() < 0: return -magnitude

		return magnitude

	// Converts to the nearest Float, or none when the magnitude is beyond the Float
	// range.
	fn to_float() Float?:
		parts := div_parts(self.num, self.den, 53)
		return binary_to_float(parts.value, parts.sticky)

	// Prints plain decimal notation with exactly `digits` fractional digits, rounding
	// ties to even. A negative digit count returns EINVAL; a result that rounds to zero
	// has no minus sign.
	fn to_fixed(digits: Int) String!:
		if digits < 0: return error(Error("bigrat: invalid input", kind: "EINVAL"))

		scaled := self.num.abs() * pow10(digits)
		var quotient = scaled / self.den
		twice := (scaled % self.den) * big(2)
		order := twice.compare(self.den)
		odd := quotient.bit_and(big(1)).sign() != 0
		if order > 0 or order == 0 and odd:
			quotient += big(1)

		var text = quotient.to_string_radix(10)

		if digits > 0:
			text = text.pad_start(digits + 1, "0")

			split_at := text.scalar_length() - digits
			text = "{text.slice(0, split_at).get("")}.{text.slice(split_at, text.scalar_length()).get("")}"

		if self.num.sign() < 0 and quotient.sign() != 0: return ok("-{text}")

		return ok(text)

	// Formats as `a/b`, or just `a` for an integer; `parse_rat` reads the result back.
	fn format() String:
		if self.is_integer(): return self.num.to_string_radix(10)
		return "{self.num.to_string_radix(10)}/{self.den.to_string_radix(10)}"

// Returns `numerator / denominator` in lowest terms; a zero denominator returns EINVAL.
export fn rat(numerator: BigInt, denominator: BigInt) BigRat!:
	if denominator.sign() == 0:
		return error(Error("bigrat: invalid input", kind: "EINVAL"))
	if numerator.sign() == 0: return ok(BigRat(num: big(0), den: big(1)))

	return ok(reduced(numerator, denominator))

// Returns the integer `value` as a fraction.
export fn rat_of_int(value: Int) BigRat:
	return BigRat(num: big(value), den: big(1))

// Returns an integer as a fraction.
export fn rat_of_big_int(value: BigInt) BigRat:
	return BigRat(num: value.clone(), den: big(1))

// Returns the exact value of a Float, such as 0.5 for 0.5 and
// 3602879701896397/36028797018963968 for 0.1. Returns none for NaN and infinities.
export fn rat_of_float(value: Float) BigRat?:
	if not value.is_finite(): return none
	if value == 0.0: return rat_of_int(0)

	parts := frexp(value)
	mantissa := ldexp(parts.fraction, 53).truncate_to_int().get(0)
	return rat_of_binary(big(mantissa), parts.exponent - 53)

// Returns the exact value `mantissa * 2^exponent`. A result needing more than 16777216
// bits faults.
export fn rat_of_binary(mantissa: BigInt, exponent: Int) BigRat:
	if exponent >= 0: return BigRat(num: shl(mantissa, exponent), den: big(1))
	return reduced(mantissa.clone(), shl(big(1), -exponent))

fn parse_digits(text: String) BigInt!:
	if value := parse_big(text): return ok(value)
	return error(Error("bigrat: invalid data", kind: "EBADMSG"))

// Parses `a/b`, an integer, or a decimal with an optional exponent: `3/4`, `-12`,
// `1.25`, `6.02e23`, `5e-3`. A zero denominator returns EINVAL, malformed text EBADMSG
// and an exponent beyond 100000 in magnitude EOVERFLOW.
export fn parse_rat(text: String) BigRat!:
	slash := text.split("/")
	if slash.length() > 2: return error(Error("bigrat: invalid data", kind: "EBADMSG"))

	if slash.length() == 2:
		top := parse_digits(slash[0])?
		bottom := parse_digits(slash[1])?
		return rat(top, bottom)

	exponent_parts := text.lower().split("e")
	if exponent_parts.length() > 2:
		return error(Error("bigrat: invalid data", kind: "EBADMSG"))

	var exponent = 0

	if exponent_parts.length() == 2:
		// `parse_exponent` takes the one optional sign itself, so a second sign is malformed.
		exponent = parse_exponent(exponent_parts[1])?
		if exponent > 100000 or exponent < -100000:
			return error(Error("bigrat: limit exceeded", kind: "EOVERFLOW"))

	point := exponent_parts[0].split(".")
	if point.length() > 2: return error(Error("bigrat: invalid data", kind: "EBADMSG"))

	var fraction_digits = 0
	var joined = point[0].clone()

	if point.length() == 2:
		// A sign belongs only before the integer digits; joining the halves would hide
		// a misplaced one.
		if point[1].starts_with("+") or point[1].starts_with("-"):
			return error(Error("bigrat: invalid data", kind: "EBADMSG"))

		fraction_digits = point[1].scalar_length()
		joined = "{point[0]}{point[1]}"

	numerator := parse_digits(joined)?
	scale := fraction_digits - exponent
	if scale <= 0: return ok(BigRat(num: numerator * pow10(-scale), den: big(1)))

	return rat(numerator, pow10(scale))

// Keep malformed decimal syntax distinct from an exponent exceeding the integer range.
fn parse_exponent(text: String) Int!:
	parsed := parse_int(text, 10)
	if value := parsed: return ok(value)
	if parsed.err().kind == "ERANGE":
		return error(Error("bigrat: limit exceeded", kind: "EOVERFLOW"))

	return error(Error("bigrat: invalid data", kind: "EBADMSG"))

// The largest supported precision in bits.
export max_big_float_precision: Int := 1000000

/*
An arbitrary-precision binary floating-point number, `mantissa * 2^exponent`, whose mantissa holds at most `precision` bits.
Every operation rounds once, to nearest with ties to even, at the larger operand precision, so results are exact
up to that single rounding. Zero is unsigned and there are no infinities or NaN: out-of-domain operations return a Result.
Example: `big_float_of_int(2, 100).sqrt()` gives the square root of two to 100 bits, and `to_fixed(30)` prints it.
*/
export opaque type BigFloat:
	// The signed integer mantissa, at most `prec` bits; zero when the value is zero.
	mant: BigInt
	// The power of two multiplying the mantissa.
	exp: Int
	// The precision in bits, 1 through 1000000.
	prec: Int

impl BigFloat:
	// Returns the precision in bits.
	fn precision() Int:
		return self.prec

	// Returns an independent copy.
	fn clone() BigFloat:
		return BigFloat(mant: self.mant.clone(), exp: self.exp, prec: self.prec)

	// Returns this value rounded to `precision` bits; a precision outside 1 through
	// 1000000 is a fault.
	fn with_precision(precision: Int) BigFloat:
		bits := checked(precision)
		return make(round_to(self.mant, self.exp, false, bits), bits)

	// Returns -1, 0 or 1 by sign.
	fn sign() Int:
		return self.mant.sign()

	// Returns the same magnitude with the opposite sign and unchanged precision; zero
	// stays zero.
	fn negate() BigFloat:
		return BigFloat(mant: -self.mant, exp: self.exp, prec: self.prec)

	// Returns the absolute value.
	fn abs() BigFloat:
		return BigFloat(mant: self.mant.abs(), exp: self.exp, prec: self.prec)

	// Returns the sum, rounded once at the larger operand precision.
	fn add(other: BigFloat) BigFloat:
		bits := larger(self.prec, other.prec)
		if self.mant.sign() == 0:
			return make(round_to(other.mant, other.exp, false, bits), bits)
		if other.mant.sign() == 0:
			return make(round_to(self.mant, self.exp, false, bits), bits)

		top_self := self.exp + bit_length(self.mant)
		top_other := other.exp + bit_length(other.mant)
		if top_self - top_other > bits + 2:
			return make(absorb(self.mant, self.exp, other.mant.sign(), bits), bits)
		if top_other - top_self > bits + 2:
			return make(absorb(other.mant, other.exp, self.mant.sign(), bits), bits)

		low := smaller(self.exp, other.exp)
		total := shl(self.mant, self.exp - low) + shl(other.mant, other.exp - low)
		return make(round_to(total, low, false, bits), bits)

	// Returns the difference, rounded once at the larger operand precision.
	fn subtract(other: BigFloat) BigFloat:
		return self.add(other.negate())

	// Returns the product, rounded once at the larger operand precision.
	fn multiply(other: BigFloat) BigFloat:
		bits := larger(self.prec, other.prec)
		return make(
			round_to(
				self.mant * other.mant,
				self.exp + other.exp,
				false,
				bits,
			),
			bits,
		)

	// Returns the quotient, rounded once at the larger operand precision; a zero
	// divisor returns EINVAL.
	fn divide(other: BigFloat) BigFloat!:
		if other.mant.sign() == 0:
			return error(Error("bigfloat: invalid input", kind: "EINVAL"))

		bits := larger(self.prec, other.prec)
		var top = self.mant.clone()
		if other.mant.sign() < 0:
			top = -top

		quotient := div_round(top, other.mant.abs(), bits)
		return ok(
			make(
				Binary(
					mant: quotient.mant.clone(),
					exp: quotient.exp + self.exp - other.exp,
				),
				bits,
			)
		)

	// Returns the square root rounded once; a negative operand returns EINVAL.
	fn sqrt() BigFloat!:
		if self.mant.sign() < 0:
			return error(Error("bigfloat: invalid input", kind: "EINVAL"))
		if self.mant.sign() == 0: return ok(self.clone())

		var padding = 0
		wanted := 2 * (self.prec + 2)
		if bit_length(self.mant) < wanted:
			padding = wanted - bit_length(self.mant)
		if (self.exp - padding) % 2 != 0:
			padding += 1

		scaled := shl(self.mant, padding)
		root := scaled.sqrt().get(big(0))
		sticky := (root * root).compare(scaled) != 0
		return ok(
			make(
				round_to(
					root,
					(self.exp - padding) / 2,
					sticky,
					self.prec,
				),
				self.prec,
			)
		)

	// Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`,
	// ignoring precision.
	fn compare(other: BigFloat) Int:
		if self.mant.sign() != other.mant.sign():
			return self.mant.sign().compare(other.mant.sign())
		if self.mant.sign() == 0: return 0

		// The leading bit's position orders the magnitudes without aligning them across
		// the exponent gap.
		own_top := self.exp + bit_length(self.mant)
		other_top := other.exp + bit_length(other.mant)
		if own_top != other_top: return own_top.compare(other_top) * self.mant.sign()

		low := smaller(self.exp, other.exp)
		return shl(self.mant, self.exp - low).compare(shl(other.mant, other.exp - low))

	// Returns the lesser value, or this value when they compare equal.
	fn min(other: BigFloat) BigFloat:
		if other.compare(self) < 0: return other.clone()
		return self.clone()

	// Returns the greater value, or this value when they compare equal.
	fn max(other: BigFloat) BigFloat:
		if other.compare(self) > 0: return other.clone()
		return self.clone()

	// Returns the exact value as a fraction.
	fn to_rat() BigRat:
		return rat_of_binary(self.mant, self.exp)

	// Discards the fraction toward zero.
	fn truncate() BigInt:
		if self.exp >= 0: return shl(self.mant, self.exp)

		magnitude := shr(self.mant.abs(), -self.exp)
		if self.mant.sign() < 0: return -magnitude

		return magnitude

	// Converts to the nearest Float, or none when the magnitude is beyond the Float
	// range.
	fn to_float() Float?:
		return binary_to_float(binary_of(self), false)

	// Prints plain decimal notation with exactly `digits` fractional digits, rounding
	// ties to even. A negative digit count returns EINVAL.
	fn to_fixed(digits: Int) String!:
		if text := self.to_rat().to_fixed(digits): return ok(text)
		return error(Error("bigfloat: invalid input", kind: "EINVAL"))

fn checked(precision: Int) Int:
	if precision < 1 or precision > max_big_float_precision:
		panic("precision must be 1 through 1000000, got {precision}")
	return precision

fn make(value: Binary, precision: Int) BigFloat:
	return BigFloat(mant: value.mant.clone(), exp: value.exp, prec: precision)

fn binary_of(value: BigFloat) Binary:
	return Binary(mant: value.mant.clone(), exp: value.exp)

// Returns `value` rounded to `precision` bits; a precision outside 1 through 1000000 is
// a fault.
export fn big_float_of_big_int(value: BigInt, precision: Int) BigFloat:
	bits := checked(precision)
	return make(round_to(value, 0, false, bits), bits)

// Returns `value` rounded to `precision` bits; a precision outside 1 through 1000000 is
// a fault.
export fn big_float_of_int(value: Int, precision: Int) BigFloat:
	return big_float_of_big_int(big(value), precision)

// Returns a Float rounded to `precision` bits (exact when precision is at least 53), or
// none for NaN and infinities.
export fn big_float_of_float(value: Float, precision: Int) BigFloat?:
	bits := checked(precision)
	if not value.is_finite(): return none
	if value == 0.0: return big_float_of_int(0, bits)

	parts := frexp(value)
	mantissa := ldexp(parts.fraction, 53).truncate_to_int().get(0)
	return make(round_to(big(mantissa), parts.exponent - 53, false, bits), bits)

// Returns the rational rounded once to `precision` bits.
export fn big_float_of_rat(value: BigRat, precision: Int) BigFloat:
	bits := checked(precision)
	return make(div_round(value.numerator(), value.denominator(), bits), bits)

// Parses an integer or decimal with optional exponent (`2`, `-0.1`, `6.02e23`) and
// rounds once to `precision` bits. Malformed text returns EBADMSG and an exponent
// beyond 100000 in magnitude EOVERFLOW.
export fn parse_big_float(text: String, precision: Int) BigFloat!:
	bits := checked(precision)
	if text.contains("/"):
		return error(Error("bigfloat: invalid data", kind: "EBADMSG"))
	if value := parse_rat(text): return ok(big_float_of_rat(value, bits))

	too_large: BigRat! := error(Error("bigrat: limit exceeded", kind: "EOVERFLOW"))
	if parse_rat(text) == too_large:
		return error(Error("bigfloat: limit exceeded", kind: "EOVERFLOW"))

	return error(Error("bigfloat: invalid data", kind: "EBADMSG"))

fn larger(left: Int, right: Int) Int:
	if left >= right: return left
	return right

fn smaller(left: Int, right: Int) Int:
	if left <= right: return left
	return right

// Adds a nonzero value too small to reach `prec` bits of `leading`: nudges `leading` by
// a quarter unit toward the small value's sign.
fn absorb(leading: BigInt, exp: Int, nudge: Int, prec: Int) Binary:
	padding := prec + 4 - bit_length(leading)
	var widened = leading.clone()
	var low = exp

	if padding > 0:
		widened = shl(leading, padding)
		low = exp - padding

	tilted := shl(widened, 2) + big(nudge)
	return round_to(tilted, low - 2, false, prec)

// A binary floating-point value `mant * 2^exp` with a signed integer mantissa.
type Binary:
	mant: BigInt
	exp: Int

fn big(value: Int) BigInt:
	return from_int(value)

fn parse_big(text: String) BigInt?:
	if value := parse(text, 10): return value
	return none

fn shl(value: BigInt, count: Int) BigInt:
	if result := value.shift_left(count): return result

	panic("bigrat: shift count out of range")

fn shr(value: BigInt, count: Int) BigInt:
	if result := value.shift_right(count): return result

	panic("bigrat: shift count out of range")

fn pow10(count: Int) BigInt:
	if result := from_int(10).pow(count): return result

	panic("pow10: negative or oversized exponent")

// Returns the number of bits in the magnitude, 0 for zero.
fn bit_length(value: BigInt) Int:
	if value.sign() == 0: return 0
	return value.abs().to_string_radix(2).length()

// Returns the floor of `numerator / denominator` for a positive denominator.
fn floor_div(numerator: BigInt, denominator: BigInt) BigInt:
	quotient := numerator / denominator
	if (numerator % denominator).sign() < 0: return quotient - from_int(1)

	return quotient

// Rounds `mant * 2^exp` to `prec` significant bits, ties to even. `sticky` says nonzero
// bits lie below `mant`; when set, `mant` must carry at least `prec + 2` bits so the
// discarded tail can only break a tie upward.
fn round_to(mant: BigInt, exp: Int, sticky: Bool, prec: Int) Binary:
	magnitude := mant.abs()
	bits := bit_length(magnitude)
	if bits <= prec: return Binary(mant: mant.clone(), exp: exp)

	var shift = bits - prec
	var kept = shr(magnitude, shift)
	rest := magnitude - shl(kept, shift)
	order := rest.compare(shl(from_int(1), shift - 1))
	odd := kept.bit_and(from_int(1)).sign() != 0

	if order > 0 or order == 0 and (sticky or odd):
		kept += from_int(1)

		if bit_length(kept) > prec:
			kept = shr(kept, 1)
			shift += 1

	if mant.sign() < 0:
		kept = -kept
	return Binary(mant: kept, exp: exp + shift)

// A quotient truncated toward zero with at least `prec + 2` bits, and whether a nonzero
// remainder lay below it.
type Quotient:
	value: Binary
	sticky: Bool

fn div_parts(numerator: BigInt, denominator: BigInt, prec: Int) Quotient:
	if numerator.sign() == 0:
		return Quotient(value: Binary(mant: from_int(0), exp: 0), sticky: false)

	magnitude := numerator.abs()
	shift := max(prec + 2 + bit_length(denominator) - bit_length(magnitude), 0)
	scaled := shl(magnitude, shift)
	var quotient = scaled / denominator
	sticky := (scaled % denominator).sign() != 0
	if numerator.sign() < 0:
		quotient = -quotient
	return Quotient(value: Binary(mant: quotient, exp: -shift), sticky: sticky)

// Divides `numerator` by a positive `denominator`, rounding once to `prec` bits.
fn div_round(numerator: BigInt, denominator: BigInt, prec: Int) Binary:
	parts := div_parts(numerator, denominator, prec)
	return round_to(parts.value.mant, parts.value.exp, parts.sticky, prec)

// Converts to the nearest Float, or none when the magnitude is beyond the Float range.
// Rounds once, onto the binary64 grid: 53 significant bits for a normal result, fewer
// as the value falls into the subnormal range.
// `sticky` says nonzero bits lie below `value`, which then must carry at least 55 bits.
fn binary_to_float(value: Binary, sticky: Bool) Float?:
	if value.mant.sign() == 0: return 0.0

	magnitude := value.mant.abs()
	bits := bit_length(magnitude)
	grid := max(value.exp + bits - 1 - 52, -1074)
	var kept = magnitude.clone()
	var exponent = value.exp

	if value.exp < grid:
		shift := grid - value.exp
		exponent = grid

		if shift > bits:
			kept = from_int(0)
		else:
			kept = shr(magnitude, shift)

			rest := magnitude - shl(kept, shift)
			order := rest.compare(shl(from_int(1), shift - 1))
			odd := kept.bit_and(from_int(1)).sign() != 0
			if order > 0 or order == 0 and (sticky or odd):
				kept += from_int(1)

	if fraction := kept.to_float():
		var result = ldexp(fraction, exponent)
		if value.mant.sign() < 0:
			result = -result
		if result.is_finite(): return result

	return none

// Reduces `numerator / denominator` for a nonzero denominator.
fn reduced(numerator: BigInt, denominator: BigInt) BigRat:
	divisor := numerator.gcd(denominator)
	var top = numerator / divisor
	var bottom = denominator / divisor

	if bottom.sign() < 0:
		top = -top
		bottom = -bottom

	return BigRat(num: top, den: bottom)
