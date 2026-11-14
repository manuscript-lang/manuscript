import (
	Data, panic from "@std/core.ms",

	msstd_decimal_compare,
	msstd_decimal_parse,
	msstd_decimal_round,
	msstd_decimal_to_fixed,
	msstd_decimal_to_float,
	msstd_decimal_to_string,
	msstd_decimal_truncate_to_int from "@std/internal/decimal.ms",
)

// How a Decimal rounds to a multiple of the requested power of ten.
export enum RoundingMode:
	HalfEven  // Nearest value; an exact tie chooses the even coefficient.
	HalfAwayFromZero  // Nearest value; an exact tie rounds away from zero.
	TowardZero  // Discards the fractional coefficient toward zero.
	Floor  // Rounds toward negative infinity.
	Ceil  // Rounds toward positive infinity.

// An exact decimal value. Conversions are explicit because binary floats may round.
// ms: data
export extern type Decimal

/*
Parses decimal text exactly: an optional sign, digits with an optional fraction (digits on both sides of the point), and
an optional exponent, as in `19.99`, `-0.5` or `1e3` (the `d` literal without its suffix). Text that is empty,
malformed, has more than 34 significant digits, or has an exponent out of range gives an
`EINVAL` error. Nothing is rounded.
*/
export fn parse_decimal(text: String) Decimal!:
	return msstd_decimal_parse(text)

// Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`;
// trailing zeros do not matter.
fn Decimal.compare(other: Decimal) Int:
	return msstd_decimal_compare(self, other)

// Returns the text of this value: its coefficient and exponent as a plain decimal
// number.
fn Decimal.to_string() String:
	return msstd_decimal_to_string(self)

// Returns the lesser of this value and `other`, or this value when they compare
// equal.
fn Decimal.min(other: Decimal) Decimal:
	if other.compare(self) < 0: return other
	return self

// Returns the greater of this value and `other`, or this value when they compare
// equal.
fn Decimal.max(other: Decimal) Decimal:
	if other.compare(self) > 0: return other
	return self

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault.
fn Decimal.clamp(low: Decimal, high: Decimal) Decimal:
	if low.compare(high) > 0:
		panic("clamp: low must not be greater than high")
	if self.compare(low) < 0: return low
	if self.compare(high) > 0: return high

	return self

// Converts to the nearest Float, which can lose precision because binary floats
// cannot represent most decimal fractions exactly. Returns none when the value is
// beyond the Float range.
fn Decimal.to_float() Float?:
	value := msstd_decimal_to_float(self)
	if value.is_finite(): return value

	return none

// Discards the fractional part toward zero and returns the integer, so -2.9 gives
// -2. Returns none when the integer part does not fit in the platform's Int.
fn Decimal.truncate_to_int() Int?:
	return msstd_decimal_truncate_to_int(self)

/*
Rounds exactly to a multiple of `10^-places`, without converting to Float.
Places range from -6144 through 6176; negative places round tens, hundreds, etc.
Invalid places return EINVAL; an unrepresentable result returns ERANGE.
Omitted or `none` mode selects HalfEven. This does not preserve trailing zeros or change arithmetic.
*/
fn Decimal.round(places: Int, mode: RoundingMode?) Decimal!:
	return msstd_decimal_round(self, places, mode)

/*
Rounds exactly and prints plain decimal notation with exactly `digits` fractional digits.
Digits range from 0 through 6176; invalid digits return EINVAL.
HalfEven is the default; rounded zero has no minus sign. Trailing zeros are retained.
*/
fn Decimal.to_fixed(digits: Int, mode: RoundingMode?) String!:
	return msstd_decimal_to_fixed(self, digits, mode)
