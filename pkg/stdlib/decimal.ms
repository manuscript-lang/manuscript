# Canonical standard-library declarations. Implementations are native.

import NumberError from "@std/numbers.ms"

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
export type Decimal:
    fn to_float() -> Float:
    # Rounds directly to IEEE binary64, without a default Float intermediate.
    fn to_float64() -> Float64:
    fn truncate_to_int() -> Optional[Int]:
    # Truncates exactly toward zero, returning none outside signed64.
    fn truncate_to_int64() -> Optional[Int64]:
    # Rounds exactly to a multiple of `10^-places`, without converting to Float.
    # Places range from -6144 through 6176; negative places round tens, hundreds, etc.
    # Invalid places return InvalidInput; an unrepresentable result returns OutOfRange.
    # Omitted or `none` mode selects HalfEven. This does not preserve trailing zeros or change arithmetic.
    fn round(
        places: Int,
        mode: Optional[RoundingMode] = none
    ) -> Result[Decimal, NumberError]:
    # Rounds exactly and prints plain decimal notation with exactly `digits` fractional digits.
    # Digits range from 0 through 6176; invalid digits return InvalidInput.
    # HalfEven is the default; rounded zero has no minus sign. Trailing zeros are retained.
    fn to_fixed(
        digits: Int,
        mode: Optional[RoundingMode] = none
    ) -> Result[String, NumberError]:
