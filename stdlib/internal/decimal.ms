import Decimal, RoundingMode from "@std/math/decimal.ms"
import NumberError from "@std/math/math.ms"

export extern fn msstd_decimal_compare(left: Decimal, right: Decimal) Int

export extern fn msstd_decimal_to_float(value: Decimal) Float

export extern fn msstd_decimal_truncate_to_int(value: Decimal) Int?

export extern fn msstd_decimal_round(
    value: Decimal,
    places: Int,
    mode: RoundingMode?
) Decimal!NumberError

export extern fn msstd_decimal_to_fixed(
    value: Decimal,
    digits: Int,
    mode: RoundingMode?
) String!NumberError
