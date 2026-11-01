import BigInt, BigIntError, NumberError from "@std/math/math.ms"

export extern fn msstd_math_acos(value: Float) Float

export extern fn msstd_math_asin(value: Float) Float

export extern fn msstd_math_atan(value: Float) Float

export extern fn msstd_math_atan2(y: Float, x: Float) Float

export extern fn msstd_math_ceil(value: Float) Float

export extern fn msstd_math_cos(value: Float) Float

export extern fn msstd_math_cosh(value: Float) Float

export extern fn msstd_math_exp(value: Float) Float

export extern fn msstd_math_floor(value: Float) Float

export extern fn msstd_math_hypot(left: Float, right: Float) Float

export extern fn msstd_math_log(value: Float) Float

export extern fn msstd_math_log10(value: Float) Float

export extern fn msstd_math_log2(value: Float) Float

export extern fn msstd_math_pow(base: Float, exponent: Float) Float

export extern fn msstd_math_remainder(left: Float, right: Float) Float

export extern fn msstd_math_round(value: Float) Float

export extern fn msstd_math_sin(value: Float) Float

export extern fn msstd_math_sinh(value: Float) Float

export extern fn msstd_math_sqrt(value: Float) Float

export extern fn msstd_math_tan(value: Float) Float

export extern fn msstd_math_tanh(value: Float) Float

export extern fn msstd_math_truncate(value: Float) Float

export extern fn msstd_math_acosh(value: Float) Float

export extern fn msstd_math_asinh(value: Float) Float

export extern fn msstd_math_atanh(value: Float) Float

export extern fn msstd_math_cbrt(value: Float) Float

export extern fn msstd_math_expm1(value: Float) Float

export extern fn msstd_math_log1p(value: Float) Float

export extern fn msstd_math_is_integer(value: Float) Bool

export extern fn msstd_math_is_safe_integer(value: Float) Bool

export extern fn msrt_bits_bit_and(left: Int, right: Int) Int

export extern fn msrt_bits_bit_or(left: Int, right: Int) Int

export extern fn msrt_bits_bit_xor(left: Int, right: Int) Int

export extern fn msrt_bits_bit_not(value: Int) Int

export extern fn msrt_bits_shift_left(value: Int, count: Int) Int

export extern fn msrt_bits_shift_right(value: Int, count: Int) Int

export extern fn msrt_bits_shift_right_unsigned(value: Int, count: Int) Int

export extern fn msrt_bits_rotate_left(value: Int, count: Int) Int

export extern fn msrt_bits_rotate_right(value: Int, count: Int) Int

export extern fn msrt_bits_count_ones(value: Int) Int

export extern fn msrt_bits_leading_zeros(value: Int) Int

export extern fn msrt_bits_trailing_zeros(value: Int) Int

export extern fn msrt_bits_wrapping_add(left: Int, right: Int) Int

export extern fn msrt_bits_wrapping_subtract(left: Int, right: Int) Int

export extern fn msrt_bits_wrapping_multiply(left: Int, right: Int) Int

export extern fn msrt_numbers_parse_float(text: String) Float!NumberError

export extern fn msrt_numbers_parse_int(text: String, radix: Int) Int!NumberError

export extern fn msstd_bigint_add(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_subtract(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_multiply(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_divide(value: BigInt, other: BigInt) BigInt!BigIntError

export extern fn msstd_bigint_remainder(value: BigInt, other: BigInt) BigInt!BigIntError

export extern fn msstd_bigint_quotient(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_modulo(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_compare(value: BigInt, other: BigInt) Int

export extern fn msstd_bigint_bit_and(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_bit_or(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_bit_xor(value: BigInt, other: BigInt) BigInt

export extern fn msstd_bigint_bit_not(value: BigInt) BigInt

export extern fn msstd_bigint_negate(value: BigInt) BigInt

export extern fn msstd_bigint_abs(value: BigInt) BigInt

export extern fn msstd_bigint_sign(value: BigInt) Int

export extern fn msstd_bigint_pow(value: BigInt, exponent: Int) BigInt!BigIntError

export extern fn msstd_bigint_shift_left(value: BigInt, count: Int) BigInt!BigIntError

export extern fn msstd_bigint_shift_right(value: BigInt, count: Int) BigInt!BigIntError

export extern fn msstd_bigint_to_float(value: BigInt) Float

export extern fn msstd_bigint_to_int(value: BigInt) Int?

export extern fn msstd_bigint_to_string_radix(value: BigInt, radix: Int) String

export extern fn msstd_bigint_from_int(value: Int) BigInt

export extern fn msstd_bigint_parse(
    text: String,
    radix: Int,
    max_digits: Int?
) BigInt!BigIntError
