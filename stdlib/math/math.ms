import Data, panic from "@std/core.ms"
import msstd_math_acos, msstd_math_asin, msstd_math_atan, msstd_math_atan2, msstd_math_ceil, msstd_math_cos, msstd_math_cosh, msstd_math_exp, msstd_math_floor, msstd_math_hypot, msstd_math_log, msstd_math_log10, msstd_math_log2, msstd_math_pow, msstd_math_remainder, msstd_math_round, msstd_math_sin, msstd_math_sinh, msstd_math_sqrt, msstd_math_tan, msstd_math_tanh, msstd_math_truncate, msstd_math_acosh, msstd_math_asinh, msstd_math_atanh, msstd_math_cbrt, msstd_math_expm1, msstd_math_log1p, msstd_math_is_integer, msstd_math_is_safe_integer, msrt_bits_bit_and, msrt_bits_bit_or, msrt_bits_bit_xor, msrt_bits_bit_not, msrt_bits_shift_left, msrt_bits_shift_right, msrt_bits_shift_right_unsigned, msrt_bits_rotate_left, msrt_bits_rotate_right, msrt_bits_count_ones, msrt_bits_leading_zeros, msrt_bits_trailing_zeros, msrt_bits_wrapping_add, msrt_bits_wrapping_subtract, msrt_bits_wrapping_multiply, msrt_numbers_parse_float, msrt_numbers_parse_int, msstd_bigint_add, msstd_bigint_subtract, msstd_bigint_multiply, msstd_bigint_divide, msstd_bigint_remainder, msstd_bigint_quotient, msstd_bigint_modulo, msstd_bigint_compare, msstd_bigint_bit_and, msstd_bigint_bit_or, msstd_bigint_bit_xor, msstd_bigint_bit_not, msstd_bigint_negate, msstd_bigint_abs, msstd_bigint_sign, msstd_bigint_pow, msstd_bigint_shift_left, msstd_bigint_shift_right, msstd_bigint_to_float, msstd_bigint_to_int, msstd_bigint_to_string_radix, msstd_bigint_from_int, msstd_bigint_parse from "@std/internal/math.ms"

# Returns the inverse cosine in radians.
export fn acos(value: Float) Float:
    return msstd_math_acos(value)

# Returns the inverse sine in radians.
export fn asin(value: Float) Float:
    return msstd_math_asin(value)

# Returns the inverse tangent in radians.
export fn atan(value: Float) Float:
    return msstd_math_atan(value)

# Returns the angle in radians for `(x, y)`, preserving its quadrant.
export fn atan2(y: Float, x: Float) Float:
    return msstd_math_atan2(y, x)

# Rounds upward to the nearest whole number.
export fn ceil(value: Float) Float:
    return msstd_math_ceil(value)

# Returns the cosine of an angle in radians.
export fn cos(value: Float) Float:
    return msstd_math_cos(value)

# Returns the hyperbolic cosine.
export fn cosh(value: Float) Float:
    return msstd_math_cosh(value)

# Euler's number, the base of natural logarithms.
export let e: Float = 2.718281828459045

# Returns e raised to `value`.
export fn exp(value: Float) Float:
    return msstd_math_exp(value)

# Rounds downward to the nearest whole number.
export fn floor(value: Float) Float:
    return msstd_math_floor(value)

# Returns the length of the hypotenuse for sides `left` and `right`.
export fn hypot(left: Float, right: Float) Float:
    return msstd_math_hypot(left, right)

# Returns the natural logarithm.
export fn log(value: Float) Float:
    return msstd_math_log(value)

# Returns the base-10 logarithm.
export fn log10(value: Float) Float:
    return msstd_math_log10(value)

# Returns the base-2 logarithm.
export fn log2(value: Float) Float:
    return msstd_math_log2(value)

# Returns the greater of two values, or `left` when they compare equal. Float orders NaN above every other value, so a NaN operand makes the result NaN.
export fn max[T: Comparable](left: T, right: T) T:
    if right.compare(left) > 0:
        return right

    return left

# Returns the lesser of two values, or `left` when they compare equal. Float orders NaN above every other value.
export fn min[T: Comparable](left: T, right: T) T:
    if right.compare(left) < 0:
        return right

    return left

# Π, the ratio of a circle's circumference to its diameter.
export let pi: Float = 3.141592653589793

# Returns `base` raised to `exponent`.
export fn pow(base: Float, exponent: Float) Float:
    return msstd_math_pow(base, exponent)

# Returns the floating-point remainder of `left / right` with the sign of `left`, like Int `%` (C `fmod`), not the IEEE round-to-nearest remainder: `remainder(5.0, 3.0)` is 2.0. A zero `right` or infinite `left` gives NaN; an infinite `right` returns `left`.
export fn remainder(left: Float, right: Float) Float:
    return msstd_math_remainder(left, right)

# Rounds to the nearest whole number, with ties toward positive infinity.
export fn round(value: Float) Float:
    return msstd_math_round(value)

# Returns the sine of an angle in radians.
export fn sin(value: Float) Float:
    return msstd_math_sin(value)

# Returns the hyperbolic sine.
export fn sinh(value: Float) Float:
    return msstd_math_sinh(value)

# Returns the non-negative square root.
export fn sqrt(value: Float) Float:
    return msstd_math_sqrt(value)

# Returns the tangent of an angle in radians.
export fn tan(value: Float) Float:
    return msstd_math_tan(value)

# Returns the hyperbolic tangent.
export fn tanh(value: Float) Float:
    return msstd_math_tanh(value)

# Truncates a value toward zero.
export fn truncate(value: Float) Float:
    return msstd_math_truncate(value)

# Returns the inverse hyperbolic cosine; values below 1.0 give NaN.
export fn acosh(value: Float) Float:
    return msstd_math_acosh(value)

# Returns the inverse hyperbolic sine.
export fn asinh(value: Float) Float:
    return msstd_math_asinh(value)

# Returns the inverse hyperbolic tangent; magnitudes above 1.0 give NaN.
export fn atanh(value: Float) Float:
    return msstd_math_atanh(value)

# Returns the real cube root, which is defined for negative values.
export fn cbrt(value: Float) Float:
    return msstd_math_cbrt(value)

# Returns e raised to `value` minus one, accurate for values near zero.
export fn expm1(value: Float) Float:
    return msstd_math_expm1(value)

# Returns the natural logarithm of one plus `value`, accurate for values near zero.
export fn log1p(value: Float) Float:
    return msstd_math_log1p(value)

# Reports whether the value is finite and has no fractional part.
export fn is_integer(value: Float) Bool:
    return msstd_math_is_integer(value)

# Reports whether the value is an integer within -(2^53 - 1) through 2^53 - 1, where Float represents integers exactly.
export fn is_safe_integer(value: Float) Bool:
    return msstd_math_is_safe_integer(value)

# Positive infinity, the Float that exceeds every finite value; negate it for negative infinity.
export let infinity: Float = 1.0 / 0.0
# NaN, the Float that is not equal to itself under IEEE rules; use `is_nan()` to detect it.
export let nan: Float = 0.0 / 0.0
# The difference between 1.0 and the next larger Float.
export let epsilon: Float = 2.220446049250313e-16
# The largest finite Float.
export let max_float: Float = 1.7976931348623157e+308
# The smallest positive Float, a subnormal value.
export let min_float: Float = 5e-324
# The largest Int, 2^63 - 1.
export let max_int: Int = 9223372036854775807
# The smallest Int, -2^63.
export let min_int: Int = -9223372036854775807 - 1
# 2^53 - 1, the largest integer every smaller integer of which a Float represents exactly.
export let max_safe_integer: Int = 9007199254740991
# The smallest integer every larger integer of which a Float represents exactly, -(2^53 - 1).
export let min_safe_integer: Int = -9007199254740991
# The natural logarithm of 2.
export let ln2: Float = 0.6931471805599453
# The natural logarithm of 10.
export let ln10: Float = 2.302585092994046
# The base-2 logarithm of e.
export let log2e: Float = 1.4426950408889634
# The base-10 logarithm of e.
export let log10e: Float = 0.43429448190325176
# The square root of 2.
export let sqrt2: Float = 1.4142135623730951
# The square root of 1/2.
export let sqrt_half: Float = 0.7071067811865476

# Errors returned for invalid numeric requests, malformed text, or out-of-range values.
export type NumberError:
    # A radix or digit-count argument is outside its documented range.
    case InvalidInput
    # The text does not match the numeric syntax, such as an empty string, stray characters, or digits invalid for the radix.
    case InvalidData
    # The text is well formed but the value does not fit, such as an integer beyond the platform's Int range or a float beyond the finite range.
    case OutOfRange

# Parses a decimal floating-point number using Manuscript's numeric syntax.
export fn parse_float(text: String) Float!NumberError:
    return msrt_numbers_parse_float(text)

# Parses an integer in a radix from 2 through 36.
export fn parse_int(text: String, radix: Int) Int!NumberError:
    return msrt_numbers_parse_int(text, radix)

impl Error for NumberError:
    # Returns the fixed diagnostic `number: <reason>`, such as `number: invalid data`, without echoing the input text.
    fn message() String:
        match self:
            InvalidInput: return "number: invalid input"
            InvalidData: return "number: invalid data"
            OutOfRange: return "number: value out of range"

# Returns the bitwise AND of two integers.
export fn bit_and(left: Int, right: Int) Int:
    return msrt_bits_bit_and(left, right)

# Returns the bitwise OR of two integers.
export fn bit_or(left: Int, right: Int) Int:
    return msrt_bits_bit_or(left, right)

# Returns the bitwise exclusive OR of two integers.
export fn bit_xor(left: Int, right: Int) Int:
    return msrt_bits_bit_xor(left, right)

# Returns the bitwise complement, so every bit of the two's-complement value flips.
export fn bit_not(value: Int) Int:
    return msrt_bits_bit_not(value)

# Shifts bits toward the high end, discarding bits shifted out; `count` must be 0 through 63 or the call faults.
export fn shift_left(value: Int, count: Int) Int:
    return msrt_bits_shift_left(value, count)

# Shifts bits toward the low end, filling with the sign bit (JavaScript `>>`); `count` must be 0 through 63 or the call faults.
export fn shift_right(value: Int, count: Int) Int:
    return msrt_bits_shift_right(value, count)

# Shifts bits toward the low end, filling with zeros (JavaScript `>>>`); `count` must be 0 through 63 or the call faults.
export fn shift_right_unsigned(value: Int, count: Int) Int:
    return msrt_bits_shift_right_unsigned(value, count)

# Rotates the 64-bit pattern toward the high end; any `count` is reduced modulo 64.
export fn rotate_left(value: Int, count: Int) Int:
    return msrt_bits_rotate_left(value, count)

# Rotates the 64-bit pattern toward the low end; any `count` is reduced modulo 64.
export fn rotate_right(value: Int, count: Int) Int:
    return msrt_bits_rotate_right(value, count)

# Counts the set bits in the 64-bit pattern.
export fn count_ones(value: Int) Int:
    return msrt_bits_count_ones(value)

# Counts the zero bits above the highest set bit; zero has 64.
export fn leading_zeros(value: Int) Int:
    return msrt_bits_leading_zeros(value)

# Counts the zero bits below the lowest set bit; zero has 64.
export fn trailing_zeros(value: Int) Int:
    return msrt_bits_trailing_zeros(value)

# Adds with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_add(left: Int, right: Int) Int:
    return msrt_bits_wrapping_add(left, right)

# Subtracts with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_subtract(left: Int, right: Int) Int:
    return msrt_bits_wrapping_subtract(left, right)

# Multiplies with two's-complement wraparound instead of faulting on overflow (JavaScript `Math.imul` at 64 bits).
export fn wrapping_multiply(left: Int, right: Int) Int:
    return msrt_bits_wrapping_multiply(left, right)

# Errors returned while parsing or converting arbitrary-precision integers.
export type BigIntError:
    # The radix is outside 2 through 36, `max_digits` is negative, or a division or remainder has a zero divisor.
    case InvalidInput
    # The text is not an optionally signed integer made only of digits valid in the radix.
    case InvalidData
    # The text exceeds `max_digits` after excluding at most one leading sign; this check precedes syntax validation.
    case LimitExceeded

# An arbitrary-precision signed integer. Use the operators + - * / % and unary - for arithmetic and < <= > >= == != for comparison;
# both operands must be BigInt (convert an Int with from_int), and / or % by zero is a fault. The named methods below are the same operations;
# divide and remainder return a Result for callers that want an error value instead of a fault.
export extern type BigInt

impl Data for BigInt:

impl BigInt:
    # Returns the exact sum; arbitrary precision means it cannot overflow.
    fn add(other: BigInt) BigInt:
        return msstd_bigint_add(self, other)

    # Returns the exact difference `self - other`; it cannot overflow.
    fn subtract(other: BigInt) BigInt:
        return msstd_bigint_subtract(self, other)

    # Returns the exact product; it cannot overflow, though very large operands take proportionally longer.
    fn multiply(other: BigInt) BigInt:
        return msstd_bigint_multiply(self, other)

    # Returns the quotient truncated toward zero, so -7 divided by 2 is -3.
    # A zero divisor returns InvalidInput.
    fn divide(other: BigInt) BigInt!BigIntError:
        return msstd_bigint_divide(self, other)

    # Returns the remainder whose sign follows the dividend, so -7 remainder 2 is -1.
    # A zero divisor returns InvalidInput.
    fn remainder(other: BigInt) BigInt!BigIntError:
        return msstd_bigint_remainder(self, other)

    # Returns -1 when this value is less than `other`, 0 when equal, and 1 when greater.
    fn compare(other: BigInt) Int:
        return msstd_bigint_compare(self, other)

    # Returns the lesser of this value and `other`, or this value when they compare equal.
    fn min(other: BigInt) BigInt:
        if other.compare(self) < 0:
            return other

        return self

    # Returns the greater of this value and `other`, or this value when they compare equal.
    fn max(other: BigInt) BigInt:
        if other.compare(self) > 0:
            return other

        return self

    # Returns this value limited to `low` through `high`; `low` greater than `high` is a programming fault.
    fn clamp(low: BigInt, high: BigInt) BigInt:
        if low.compare(high) > 0:
            panic("clamp: low must not be greater than high")
        if self.compare(low) < 0:
            return low
        if self.compare(high) > 0:
            return high

        return self

    # Returns the bitwise AND using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    fn bit_and(other: BigInt) BigInt:
        return msstd_bigint_bit_and(self, other)

    # Returns the bitwise OR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    fn bit_or(other: BigInt) BigInt:
        return msstd_bigint_bit_or(self, other)

    # Returns the bitwise XOR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    fn bit_xor(other: BigInt) BigInt:
        return msstd_bigint_bit_xor(self, other)

    # Returns the bitwise complement using infinite-width two's-complement semantics, so `bit_not(x)` equals `-x - 1`.
    fn bit_not() BigInt:
        return msstd_bigint_bit_not(self)

    # Returns the value with its sign flipped.
    fn negate() BigInt:
        return msstd_bigint_negate(self)

    # Returns the absolute value, which is never negative.
    fn abs() BigInt:
        return msstd_bigint_abs(self)

    # Returns -1, 0 or 1 as the value is negative, zero or positive.
    fn sign() Int:
        return msstd_bigint_sign(self)

    # Raises to a nonnegative `exponent`. A negative exponent returns InvalidInput, and a result above 16777216 bits returns LimitExceeded.
    fn pow(exponent: Int) BigInt!BigIntError:
        return msstd_bigint_pow(self, exponent)

    # Shifts left by `count` bits, multiplying by two to that power. A negative count returns InvalidInput, and a result above 16777216 bits returns LimitExceeded.
    fn shift_left(count: Int) BigInt!BigIntError:
        return msstd_bigint_shift_left(self, count)

    # Shifts right by `count` bits with floor semantics for negatives, so -5 shifted by 1 is -3. A negative count returns InvalidInput.
    fn shift_right(count: Int) BigInt!BigIntError:
        return msstd_bigint_shift_right(self, count)

    # Converts to the nearest Float, or returns none when the magnitude exceeds the Float range.
    fn to_float() Float?:
        let value = msstd_bigint_to_float(self)
        if value.is_finite():
            return value

        return none

    # Returns the value as an Int when it fits in the platform's Int, or none when it is outside that range.
    fn to_int() Int?:
        return msstd_bigint_to_int(self)

    # Formats the value in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String:
        return msstd_bigint_to_string_radix(self, radix)

# Converts a machine-sized integer without loss.
export fn from_int(value: Int) BigInt:
    return msstd_bigint_from_int(value)

# Parses a base-2 through base-36 integer. `max_digits` bounds work when supplied.
export fn parse(text: String, radix: Int, max_digits: Int?) BigInt!BigIntError:
    return msstd_bigint_parse(text, radix, max_digits)

impl Error for BigIntError:
    # Returns the fixed diagnostic `big integer: <reason>`, such as `big integer: invalid input`, without echoing the input text.
    fn message() String:
        match self:
            InvalidInput: return "big integer: invalid input"
            InvalidData: return "big integer: invalid data"
            LimitExceeded: return "big integer: limit exceeded"
