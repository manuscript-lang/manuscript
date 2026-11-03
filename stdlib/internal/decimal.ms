import Decimal, RoundingMode from "@std/math/decimal.ms"

export extern fn msstd_decimal_compare(left: Decimal, right: Decimal) Int

export extern fn msstd_decimal_to_float(value: Decimal) Float

export extern fn msstd_decimal_truncate_to_int(value: Decimal) Int?

export extern fn msstd_decimal_round(
    value: Decimal,
    places: Int,
    mode: RoundingMode?
) Decimal!

export extern fn msstd_decimal_to_fixed(
    value: Decimal,
    digits: Int,
    mode: RoundingMode?
) String!
