import NumberError from "@std/math.ms"

# How a Decimal rounds to a multiple of the requested power of ten.
export type RoundingMode:
    # Nearest value; an exact tie chooses the even coefficient.
    case HalfEven
    # Nearest value; an exact tie rounds away from zero.
    case HalfAwayFromZero
    # Discards the fractional coefficient toward zero.
    case TowardZero
    # Rounds toward negative infinity.
    case Floor
    # Rounds toward positive infinity.
    case Ceil

# An exact decimal value. Conversions are explicit because binary floats may round.
export extern type Decimal

extern fn msstd_decimal_compare(left: Decimal, right: Decimal) Int

extern fn msstd_decimal_to_float(value: Decimal) Float

extern fn msstd_decimal_truncate_to_int(value: Decimal) Optional[Int]

extern fn msstd_decimal_round(
    value: Decimal,
    places: Int,
    mode: Optional[RoundingMode]
) Result[Decimal, NumberError]

extern fn msstd_decimal_to_fixed(
    value: Decimal,
    digits: Int,
    mode: Optional[RoundingMode]
) Result[String, NumberError]

impl Decimal:
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`; trailing zeros do not matter.
    fn compare(other: Decimal) Int:
        return msstd_decimal_compare(self, other)

    # Converts to the nearest Float, which can lose precision because binary floats cannot represent most decimal fractions exactly.
    # Values beyond the Float range convert to an infinity.
    fn to_float() Float:
        return msstd_decimal_to_float(self)

    # Discards the fractional part toward zero and returns the integer, so -2.9 gives -2.
    # Returns none when the integer part does not fit in the platform's Int.
    fn truncate_to_int() Optional[Int]:
        return msstd_decimal_truncate_to_int(self)

    # Rounds exactly to a multiple of `10^-places`, without converting to Float.
    # Places range from -6144 through 6176; negative places round tens, hundreds, etc.
    # Invalid places return InvalidInput; an unrepresentable result returns OutOfRange.
    # Omitted or `none` mode selects HalfEven. This does not preserve trailing zeros or change arithmetic.
    fn round(
        places: Int,
        mode: Optional[RoundingMode] = none
    ) Result[Decimal, NumberError]:
        return msstd_decimal_round(self, places, mode)

    # Rounds exactly and prints plain decimal notation with exactly `digits` fractional digits.
    # Digits range from 0 through 6176; invalid digits return InvalidInput.
    # HalfEven is the default; rounded zero has no minus sign. Trailing zeros are retained.
    fn to_fixed(
        digits: Int,
        mode: Optional[RoundingMode] = none
    ) Result[String, NumberError]:
        return msstd_decimal_to_fixed(self, digits, mode)
