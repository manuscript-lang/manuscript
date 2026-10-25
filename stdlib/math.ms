extern def msstd_math_acos(value: Float) -> Float

extern def msstd_math_asin(value: Float) -> Float

extern def msstd_math_atan(value: Float) -> Float

extern def msstd_math_atan2(y: Float, x: Float) -> Float

extern def msstd_math_ceil(value: Float) -> Float

extern def msstd_math_cos(value: Float) -> Float

extern def msstd_math_cosh(value: Float) -> Float

extern def msstd_math_e() -> Float

extern def msstd_math_exp(value: Float) -> Float

extern def msstd_math_floor(value: Float) -> Float

extern def msstd_math_hypot(left: Float, right: Float) -> Float

extern def msstd_math_log(value: Float) -> Float

extern def msstd_math_log10(value: Float) -> Float

extern def msstd_math_log2(value: Float) -> Float

extern def msstd_math_pi() -> Float

extern def msstd_math_pow(base: Float, exponent: Float) -> Float

extern def msstd_math_remainder(left: Float, right: Float) -> Float

extern def msstd_math_round(value: Float) -> Float

extern def msstd_math_sin(value: Float) -> Float

extern def msstd_math_sinh(value: Float) -> Float

extern def msstd_math_sqrt(value: Float) -> Float

extern def msstd_math_tan(value: Float) -> Float

extern def msstd_math_tanh(value: Float) -> Float

extern def msstd_math_truncate(value: Float) -> Float

extern def msstd_math_acosh(value: Float) -> Float

extern def msstd_math_asinh(value: Float) -> Float

extern def msstd_math_atanh(value: Float) -> Float

extern def msstd_math_cbrt(value: Float) -> Float

extern def msstd_math_expm1(value: Float) -> Float

extern def msstd_math_log1p(value: Float) -> Float

extern def msstd_math_is_integer(value: Float) -> Bool

extern def msstd_math_is_safe_integer(value: Float) -> Bool

extern def msstd_math_infinity() -> Float

extern def msstd_math_nan() -> Float

extern def msstd_math_epsilon() -> Float

extern def msstd_math_max_float() -> Float

extern def msstd_math_min_float() -> Float

extern def msstd_math_max_int() -> Int

extern def msstd_math_min_int() -> Int

extern def msstd_math_max_safe_integer() -> Int

extern def msstd_math_min_safe_integer() -> Int

extern def msstd_math_ln2() -> Float

extern def msstd_math_ln10() -> Float

extern def msstd_math_log2e() -> Float

extern def msstd_math_log10e() -> Float

extern def msstd_math_sqrt2() -> Float

extern def msstd_math_sqrt_half() -> Float

extern def msrt_numbers_parse_float(text: String) -> Result[Float, NumberError]

extern def msrt_numbers_parse_int(text: String, radix: Int) -> Result[Int, NumberError]

extern def msrt_bits_bit_and(left: Int, right: Int) -> Int

extern def msrt_bits_bit_or(left: Int, right: Int) -> Int

extern def msrt_bits_bit_xor(left: Int, right: Int) -> Int

extern def msrt_bits_bit_not(value: Int) -> Int

extern def msrt_bits_shift_left(value: Int, count: Int) -> Int

extern def msrt_bits_shift_right(value: Int, count: Int) -> Int

extern def msrt_bits_shift_right_unsigned(value: Int, count: Int) -> Int

extern def msrt_bits_rotate_left(value: Int, count: Int) -> Int

extern def msrt_bits_rotate_right(value: Int, count: Int) -> Int

extern def msrt_bits_count_ones(value: Int) -> Int

extern def msrt_bits_leading_zeros(value: Int) -> Int

extern def msrt_bits_trailing_zeros(value: Int) -> Int

extern def msrt_bits_wrapping_add(left: Int, right: Int) -> Int

extern def msrt_bits_wrapping_subtract(left: Int, right: Int) -> Int

extern def msrt_bits_wrapping_multiply(left: Int, right: Int) -> Int

extern def msstd_bigint_add(value: BigInt, other: BigInt) -> BigInt

extern def msstd_bigint_subtract(value: BigInt, other: BigInt) -> BigInt

extern def msstd_bigint_multiply(value: BigInt, other: BigInt) -> BigInt

extern def msstd_bigint_divide(
    value: BigInt,
    other: BigInt
) -> Result[BigInt, BigIntError]

extern def msstd_bigint_remainder(
    value: BigInt,
    other: BigInt
) -> Result[BigInt, BigIntError]

extern def msstd_bigint_compare(value: BigInt, other: BigInt) -> Int

extern def msstd_bigint_bit_and(value: BigInt, other: BigInt) -> BigInt

extern def msstd_bigint_bit_or(value: BigInt, other: BigInt) -> BigInt

extern def msstd_bigint_bit_xor(value: BigInt, other: BigInt) -> BigInt

extern def msstd_bigint_bit_not(value: BigInt) -> BigInt

extern def msstd_bigint_negate(value: BigInt) -> BigInt

extern def msstd_bigint_abs(value: BigInt) -> BigInt

extern def msstd_bigint_sign(value: BigInt) -> Int

extern def msstd_bigint_pow(value: BigInt, exponent: Int) -> Result[BigInt, BigIntError]

extern def msstd_bigint_shift_left(
    value: BigInt,
    count: Int
) -> Result[BigInt, BigIntError]

extern def msstd_bigint_shift_right(
    value: BigInt,
    count: Int
) -> Result[BigInt, BigIntError]

extern def msstd_bigint_to_float(value: BigInt) -> Float

extern def msstd_bigint_to_int(value: BigInt) -> Optional[Int]

extern def msstd_bigint_to_string_radix(value: BigInt, radix: Int) -> String

extern def msstd_bigint_from_int(value: Int) -> BigInt

extern def msstd_bigint_parse(
    text: String,
    radix: Int,
    max_digits: Optional[Int]
) -> Result[BigInt, BigIntError]

# Returns the inverse cosine in radians.
export def acos(value: Float) -> Float:
    return msstd_math_acos(value)

# Returns the inverse sine in radians.
export def asin(value: Float) -> Float:
    return msstd_math_asin(value)

# Returns the inverse tangent in radians.
export def atan(value: Float) -> Float:
    return msstd_math_atan(value)

# Returns the angle in radians for `(x, y)`, preserving its quadrant.
export def atan2(y: Float, x: Float) -> Float:
    return msstd_math_atan2(y, x)

# Rounds upward to the nearest whole number.
export def ceil(value: Float) -> Float:
    return msstd_math_ceil(value)

# Returns the cosine of an angle in radians.
export def cos(value: Float) -> Float:
    return msstd_math_cos(value)

# Returns the hyperbolic cosine.
export def cosh(value: Float) -> Float:
    return msstd_math_cosh(value)

# Returns Euler's number, the base of natural logarithms.
export def e() -> Float:
    return msstd_math_e()

# Returns e raised to `value`.
export def exp(value: Float) -> Float:
    return msstd_math_exp(value)

# Rounds downward to the nearest whole number.
export def floor(value: Float) -> Float:
    return msstd_math_floor(value)

# Returns the length of the hypotenuse for sides `left` and `right`.
export def hypot(left: Float, right: Float) -> Float:
    return msstd_math_hypot(left, right)

# Returns the natural logarithm.
export def log(value: Float) -> Float:
    return msstd_math_log(value)

# Returns the base-10 logarithm.
export def log10(value: Float) -> Float:
    return msstd_math_log10(value)

# Returns the base-2 logarithm.
export def log2(value: Float) -> Float:
    return msstd_math_log2(value)

# Returns the greater of two values, or `left` when they compare equal. Float orders NaN above every other value, so a NaN operand makes the result NaN.
export def max[T: Comparable](left: T, right: T) -> T:
    if right.compare(left) > 0:
        return right

    return left

# Returns the lesser of two values, or `left` when they compare equal. Float orders NaN above every other value.
export def min[T: Comparable](left: T, right: T) -> T:
    if right.compare(left) < 0:
        return right

    return left

# Returns the greatest of the values, keeping the first of equal ones, or none for an empty list. Float orders NaN above every other value.
export def max_of[T: Comparable & Clonable](values: List[T]) -> Optional[T]:
    var best: Optional[T] = none

    for item in values:
        if let current = best:
            if item.compare(current) > 0:
                best = some(item.clone())
        else:
            best = some(item.clone())

    return best

# Returns the least of the values, keeping the first of equal ones, or none for an empty list. Float orders NaN above every other value.
export def min_of[T: Comparable & Clonable](values: List[T]) -> Optional[T]:
    var best: Optional[T] = none

    for item in values:
        if let current = best:
            if item.compare(current) < 0:
                best = some(item.clone())
        else:
            best = some(item.clone())

    return best

# Returns π, the ratio of a circle's circumference to its diameter.
export def pi() -> Float:
    return msstd_math_pi()

# Returns `base` raised to `exponent`.
export def pow(base: Float, exponent: Float) -> Float:
    return msstd_math_pow(base, exponent)

# Returns the floating-point remainder of `left / right` with the sign of `left`, like Int `%` (C `fmod`), not the IEEE round-to-nearest remainder: `remainder(5.0, 3.0)` is 2.0. A zero `right` or infinite `left` gives NaN; an infinite `right` returns `left`.
export def remainder(left: Float, right: Float) -> Float:
    return msstd_math_remainder(left, right)

# Rounds to the nearest whole number, with ties toward positive infinity.
export def round(value: Float) -> Float:
    return msstd_math_round(value)

# Returns the sine of an angle in radians.
export def sin(value: Float) -> Float:
    return msstd_math_sin(value)

# Returns the hyperbolic sine.
export def sinh(value: Float) -> Float:
    return msstd_math_sinh(value)

# Returns the non-negative square root.
export def sqrt(value: Float) -> Float:
    return msstd_math_sqrt(value)

# Returns the tangent of an angle in radians.
export def tan(value: Float) -> Float:
    return msstd_math_tan(value)

# Returns the hyperbolic tangent.
export def tanh(value: Float) -> Float:
    return msstd_math_tanh(value)

# Truncates a value toward zero.
export def truncate(value: Float) -> Float:
    return msstd_math_truncate(value)

# Returns the inverse hyperbolic cosine; values below 1.0 give NaN.
export def acosh(value: Float) -> Float:
    return msstd_math_acosh(value)

# Returns the inverse hyperbolic sine.
export def asinh(value: Float) -> Float:
    return msstd_math_asinh(value)

# Returns the inverse hyperbolic tangent; magnitudes above 1.0 give NaN.
export def atanh(value: Float) -> Float:
    return msstd_math_atanh(value)

# Returns the real cube root, which is defined for negative values.
export def cbrt(value: Float) -> Float:
    return msstd_math_cbrt(value)

# Returns e raised to `value` minus one, accurate for values near zero.
export def expm1(value: Float) -> Float:
    return msstd_math_expm1(value)

# Returns the natural logarithm of one plus `value`, accurate for values near zero.
export def log1p(value: Float) -> Float:
    return msstd_math_log1p(value)

# Reports whether the value is finite and has no fractional part.
export def is_integer(value: Float) -> Bool:
    return msstd_math_is_integer(value)

# Reports whether the value is an integer within -(2^53 - 1) through 2^53 - 1, where Float represents integers exactly.
export def is_safe_integer(value: Float) -> Bool:
    return msstd_math_is_safe_integer(value)

# Returns positive infinity, the Float that exceeds every finite value; negate it for negative infinity.
export def infinity() -> Float:
    return msstd_math_infinity()

# Returns NaN, the Float that is not equal to itself under IEEE rules; use `is_nan()` to detect it.
export def nan() -> Float:
    return msstd_math_nan()

# Returns the difference between 1.0 and the next larger Float.
export def epsilon() -> Float:
    return msstd_math_epsilon()

# Returns the largest finite Float.
export def max_float() -> Float:
    return msstd_math_max_float()

# Returns the smallest positive Float, a subnormal value.
export def min_float() -> Float:
    return msstd_math_min_float()

# Returns the largest Int.
export def max_int() -> Int:
    return msstd_math_max_int()

# Returns the smallest Int.
export def min_int() -> Int:
    return msstd_math_min_int()

# Returns 2^53 - 1, the largest integer every smaller integer of which a Float represents exactly.
export def max_safe_integer() -> Int:
    return msstd_math_max_safe_integer()

# Returns -(2^53 - 1).
export def min_safe_integer() -> Int:
    return msstd_math_min_safe_integer()

# Returns the natural logarithm of 2.
export def ln2() -> Float:
    return msstd_math_ln2()

# Returns the natural logarithm of 10.
export def ln10() -> Float:
    return msstd_math_ln10()

# Returns the base-2 logarithm of e.
export def log2e() -> Float:
    return msstd_math_log2e()

# Returns the base-10 logarithm of e.
export def log10e() -> Float:
    return msstd_math_log10e()

# Returns the square root of 2.
export def sqrt2() -> Float:
    return msstd_math_sqrt2()

# Returns the square root of 1/2.
export def sqrt_half() -> Float:
    return msstd_math_sqrt_half()

# Errors returned for invalid numeric requests, malformed text, or out-of-range values.
export type NumberError:
    # A radix or digit-count argument is outside its documented range.
    case InvalidInput
    # The text does not match the numeric syntax, such as an empty string, stray characters, or digits invalid for the radix.
    case InvalidData
    # The text is well formed but the value does not fit, such as an integer beyond the platform's Int range or a float beyond the finite range.
    case OutOfRange

# Parses a decimal floating-point number using Manuscript's numeric syntax.
export def parse_float(text: String) -> Result[Float, NumberError]:
    return msrt_numbers_parse_float(text)

# Parses an integer in a radix from 2 through 36.
export def parse_int(text: String, radix: Int) -> Result[Int, NumberError]:
    return msrt_numbers_parse_int(text, radix)

impl Error for NumberError:
    # Returns the fixed diagnostic `number: <reason>`, such as `number: invalid data`, without echoing the input text.
    def message() -> String:
        match self:
            case InvalidInput: return "number: invalid input"
            case InvalidData: return "number: invalid data"
            case OutOfRange: return "number: value out of range"

# Returns the bitwise AND of two integers.
export def bit_and(left: Int, right: Int) -> Int:
    return msrt_bits_bit_and(left, right)

# Returns the bitwise OR of two integers.
export def bit_or(left: Int, right: Int) -> Int:
    return msrt_bits_bit_or(left, right)

# Returns the bitwise exclusive OR of two integers.
export def bit_xor(left: Int, right: Int) -> Int:
    return msrt_bits_bit_xor(left, right)

# Returns the bitwise complement, so every bit of the two's-complement value flips.
export def bit_not(value: Int) -> Int:
    return msrt_bits_bit_not(value)

# Shifts bits toward the high end, discarding bits shifted out; `count` must be 0 through 63 or the call faults.
export def shift_left(value: Int, count: Int) -> Int:
    return msrt_bits_shift_left(value, count)

# Shifts bits toward the low end, filling with the sign bit (JavaScript `>>`); `count` must be 0 through 63 or the call faults.
export def shift_right(value: Int, count: Int) -> Int:
    return msrt_bits_shift_right(value, count)

# Shifts bits toward the low end, filling with zeros (JavaScript `>>>`); `count` must be 0 through 63 or the call faults.
export def shift_right_unsigned(value: Int, count: Int) -> Int:
    return msrt_bits_shift_right_unsigned(value, count)

# Rotates the 64-bit pattern toward the high end; any `count` is reduced modulo 64.
export def rotate_left(value: Int, count: Int) -> Int:
    return msrt_bits_rotate_left(value, count)

# Rotates the 64-bit pattern toward the low end; any `count` is reduced modulo 64.
export def rotate_right(value: Int, count: Int) -> Int:
    return msrt_bits_rotate_right(value, count)

# Counts the set bits in the 64-bit pattern.
export def count_ones(value: Int) -> Int:
    return msrt_bits_count_ones(value)

# Counts the zero bits above the highest set bit; zero has 64.
export def leading_zeros(value: Int) -> Int:
    return msrt_bits_leading_zeros(value)

# Counts the zero bits below the lowest set bit; zero has 64.
export def trailing_zeros(value: Int) -> Int:
    return msrt_bits_trailing_zeros(value)

# Adds with two's-complement wraparound instead of faulting on overflow.
export def wrapping_add(left: Int, right: Int) -> Int:
    return msrt_bits_wrapping_add(left, right)

# Subtracts with two's-complement wraparound instead of faulting on overflow.
export def wrapping_subtract(left: Int, right: Int) -> Int:
    return msrt_bits_wrapping_subtract(left, right)

# Multiplies with two's-complement wraparound instead of faulting on overflow (JavaScript `Math.imul` at 64 bits).
export def wrapping_multiply(left: Int, right: Int) -> Int:
    return msrt_bits_wrapping_multiply(left, right)

# Errors returned while parsing or converting arbitrary-precision integers.
export type BigIntError:
    # The radix is outside 2 through 36, `max_digits` is negative, or a division or remainder has a zero divisor.
    case InvalidInput
    # The text is not an optionally signed integer made only of digits valid in the radix.
    case InvalidData
    # The text exceeds `max_digits` after excluding at most one leading sign; this check precedes syntax validation.
    case LimitExceeded

# An arbitrary-precision signed integer with explicit arithmetic operations.
export extern type BigInt

impl BigInt:
    # Returns the exact sum; arbitrary precision means it cannot overflow.
    def add(other: BigInt) -> BigInt:
        return msstd_bigint_add(self, other)

    # Returns the exact difference `self - other`; it cannot overflow.
    def subtract(other: BigInt) -> BigInt:
        return msstd_bigint_subtract(self, other)

    # Returns the exact product; it cannot overflow, though very large operands take proportionally longer.
    def multiply(other: BigInt) -> BigInt:
        return msstd_bigint_multiply(self, other)

    # Returns the quotient truncated toward zero, so -7 divided by 2 is -3.
    # A zero divisor returns InvalidInput.
    def divide(other: BigInt) -> Result[BigInt, BigIntError]:
        return msstd_bigint_divide(self, other)

    # Returns the remainder whose sign follows the dividend, so -7 remainder 2 is -1.
    # A zero divisor returns InvalidInput.
    def remainder(other: BigInt) -> Result[BigInt, BigIntError]:
        return msstd_bigint_remainder(self, other)

    # Returns -1 when this value is less than `other`, 0 when equal, and 1 when greater.
    def compare(other: BigInt) -> Int:
        return msstd_bigint_compare(self, other)

    # Returns the bitwise AND using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    def bit_and(other: BigInt) -> BigInt:
        return msstd_bigint_bit_and(self, other)

    # Returns the bitwise OR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    def bit_or(other: BigInt) -> BigInt:
        return msstd_bigint_bit_or(self, other)

    # Returns the bitwise XOR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    def bit_xor(other: BigInt) -> BigInt:
        return msstd_bigint_bit_xor(self, other)

    # Returns the bitwise complement using infinite-width two's-complement semantics, so `bit_not(x)` equals `-x - 1`.
    def bit_not() -> BigInt:
        return msstd_bigint_bit_not(self)

    # Returns the value with its sign flipped.
    def negate() -> BigInt:
        return msstd_bigint_negate(self)

    # Returns the absolute value, which is never negative.
    def abs() -> BigInt:
        return msstd_bigint_abs(self)

    # Returns -1, 0 or 1 as the value is negative, zero or positive.
    def sign() -> Int:
        return msstd_bigint_sign(self)

    # Raises to a nonnegative `exponent`. A negative exponent returns InvalidInput, and a result above 16777216 bits returns LimitExceeded.
    def pow(exponent: Int) -> Result[BigInt, BigIntError]:
        return msstd_bigint_pow(self, exponent)

    # Shifts left by `count` bits, multiplying by two to that power. A negative count returns InvalidInput, and a result above 16777216 bits returns LimitExceeded.
    def shift_left(count: Int) -> Result[BigInt, BigIntError]:
        return msstd_bigint_shift_left(self, count)

    # Shifts right by `count` bits with floor semantics for negatives, so -5 shifted by 1 is -3. A negative count returns InvalidInput.
    def shift_right(count: Int) -> Result[BigInt, BigIntError]:
        return msstd_bigint_shift_right(self, count)

    # Converts to the nearest Float, or infinity of the same sign when the magnitude exceeds the Float range.
    def to_float() -> Float:
        return msstd_bigint_to_float(self)

    # Returns the value as an Int when it fits in the platform's Int, or none when it is outside that range.
    def to_int() -> Optional[Int]:
        return msstd_bigint_to_int(self)

    # Formats the value in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    def to_string_radix(radix: Int) -> String:
        return msstd_bigint_to_string_radix(self, radix)

# Converts a machine-sized integer without loss.
export def from_int(value: Int) -> BigInt:
    return msstd_bigint_from_int(value)

# Parses a base-2 through base-36 integer. `max_digits` bounds work when supplied.
export def parse(
    text: String,
    radix: Int,
    max_digits: Optional[Int] = none
) -> Result[BigInt, BigIntError]:
    return msstd_bigint_parse(text, radix, max_digits)

impl Error for BigIntError:
    # Returns the fixed diagnostic `big integer: <reason>`, such as `big integer: invalid input`, without echoing the input text.
    def message() -> String:
        match self:
            case InvalidInput: return "big integer: invalid input"
            case InvalidData: return "big integer: invalid data"
            case LimitExceeded: return "big integer: limit exceeded"
