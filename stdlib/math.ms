# Returns the absolute value of a floating-point number.
export fn abs(value: Float) Float:

# Returns the absolute value of an integer.
export fn abs_int(value: Int) Int:

# Returns the inverse cosine in radians.
export fn acos(value: Float) Float:

# Returns the inverse sine in radians.
export fn asin(value: Float) Float:

# Returns the inverse tangent in radians.
export fn atan(value: Float) Float:

# Returns the angle in radians for `(x, y)`, preserving its quadrant.
export fn atan2(y: Float, x: Float) Float:

# Rounds upward to the nearest whole number.
export fn ceil(value: Float) Float:

# Returns the cosine of an angle in radians.
export fn cos(value: Float) Float:

# Returns the hyperbolic cosine.
export fn cosh(value: Float) Float:

# Returns Euler's number, the base of natural logarithms.
export fn e() Float:

# Returns e raised to `value`.
export fn exp(value: Float) Float:

# Rounds downward to the nearest whole number.
export fn floor(value: Float) Float:

# Returns the length of the hypotenuse for sides `left` and `right`.
export fn hypot(left: Float, right: Float) Float:

# Returns the natural logarithm.
export fn log(value: Float) Float:

# Returns the base-10 logarithm.
export fn log10(value: Float) Float:

# Returns the base-2 logarithm.
export fn log2(value: Float) Float:

# Returns the greater of two values, or `left` when they compare equal. Float orders NaN above every other value, so a NaN operand makes the result NaN.
export fn max[T: Comparable](left: T, right: T) T:

# Returns the lesser of two values, or `left` when they compare equal. Float orders NaN above every other value.
export fn min[T: Comparable](left: T, right: T) T:

# Returns the greatest of the values, keeping the first of equal ones, or none for an empty list. Float orders NaN above every other value.
export fn max_of[T: Comparable](values: List[T]) Optional[T]:

# Returns the least of the values, keeping the first of equal ones, or none for an empty list. Float orders NaN above every other value.
export fn min_of[T: Comparable](values: List[T]) Optional[T]:

# Returns π, the ratio of a circle's circumference to its diameter.
export fn pi() Float:

# Returns `base` raised to `exponent`.
export fn pow(base: Float, exponent: Float) Float:

# Returns the floating-point remainder of `left / right` with the sign of `left`, like Int `%` (C `fmod`), not the IEEE round-to-nearest remainder: `remainder(5.0, 3.0)` is 2.0. A zero `right` or infinite `left` gives NaN; an infinite `right` returns `left`.
export fn remainder(left: Float, right: Float) Float:

# Rounds to the nearest whole number, with ties toward positive infinity.
export fn round(value: Float) Float:

# Returns the sine of an angle in radians.
export fn sin(value: Float) Float:

# Returns the hyperbolic sine.
export fn sinh(value: Float) Float:

# Returns the non-negative square root.
export fn sqrt(value: Float) Float:

# Returns the tangent of an angle in radians.
export fn tan(value: Float) Float:

# Returns the hyperbolic tangent.
export fn tanh(value: Float) Float:

# Truncates a value toward zero.
export fn truncate(value: Float) Float:

# Returns the inverse hyperbolic cosine; values below 1.0 give NaN.
export fn acosh(value: Float) Float:

# Returns the inverse hyperbolic sine.
export fn asinh(value: Float) Float:

# Returns the inverse hyperbolic tangent; magnitudes above 1.0 give NaN.
export fn atanh(value: Float) Float:

# Returns the real cube root, which is defined for negative values.
export fn cbrt(value: Float) Float:

# Returns e raised to `value` minus one, accurate for values near zero.
export fn expm1(value: Float) Float:

# Returns the natural logarithm of one plus `value`, accurate for values near zero.
export fn log1p(value: Float) Float:

# Returns -1.0, 0.0 or 1.0 by sign, preserving signed zero and NaN.
export fn sign(value: Float) Float:

# Returns -1, 0 or 1 as the integer is negative, zero or positive.
export fn sign_int(value: Int) Int:

# Rounds to the nearest 32-bit floating-point value and widens it back to Float.
export fn to_float32(value: Float) Float:

# Reports whether the value is finite and has no fractional part.
export fn is_integer(value: Float) Bool:

# Reports whether the value is an integer within -(2^53 - 1) through 2^53 - 1, where Float represents integers exactly.
export fn is_safe_integer(value: Float) Bool:

# Returns positive infinity, the Float that exceeds every finite value; negate it for negative infinity.
export fn infinity() Float:

# Returns NaN, the Float that is not equal to itself under IEEE rules; use `is_nan()` to detect it.
export fn nan() Float:

# Returns the difference between 1.0 and the next larger Float.
export fn epsilon() Float:

# Returns the largest finite Float.
export fn max_float() Float:

# Returns the smallest positive Float, a subnormal value.
export fn min_float() Float:

# Returns the largest Int.
export fn max_int() Int:

# Returns the smallest Int.
export fn min_int() Int:

# Returns 2^53 - 1, the largest integer every smaller integer of which a Float represents exactly.
export fn max_safe_integer() Int:

# Returns -(2^53 - 1).
export fn min_safe_integer() Int:

# Returns the natural logarithm of 2.
export fn ln2() Float:

# Returns the natural logarithm of 10.
export fn ln10() Float:

# Returns the base-2 logarithm of e.
export fn log2e() Float:

# Returns the base-10 logarithm of e.
export fn log10e() Float:

# Returns the square root of 2.
export fn sqrt2() Float:

# Returns the square root of 1/2.
export fn sqrt_half() Float:

# Errors returned for invalid numeric requests, malformed text, or out-of-range values.
export type NumberError:
    # A radix or digit-count argument is outside its documented range.
    case InvalidInput
    # The text does not match the numeric syntax, such as an empty string, stray characters, or digits invalid for the radix.
    case InvalidData
    # The text is well formed but the value does not fit, such as an integer beyond the platform's Int range or a float beyond the finite range.
    case OutOfRange

# Parses a decimal floating-point number using Manuscript's numeric syntax.
export fn parse_float(text: String) Result[Float, NumberError]:

# Parses an integer in a radix from 2 through 36.
export fn parse_int(text: String, radix: Int) Result[Int, NumberError]:

impl Error for NumberError:
    # Returns the fixed diagnostic `number: <reason>`, such as `number: invalid data`, without echoing the input text.
    fn message() String:

# Returns the bitwise AND of two integers.
export fn bit_and(left: Int, right: Int) Int:

# Returns the bitwise OR of two integers.
export fn bit_or(left: Int, right: Int) Int:

# Returns the bitwise exclusive OR of two integers.
export fn bit_xor(left: Int, right: Int) Int:

# Returns the bitwise complement, so every bit of the two's-complement value flips.
export fn bit_not(value: Int) Int:

# Shifts bits toward the high end, discarding bits shifted out; `count` must be 0 through 63 or the call faults.
export fn shift_left(value: Int, count: Int) Int:

# Shifts bits toward the low end, filling with the sign bit (JavaScript `>>`); `count` must be 0 through 63 or the call faults.
export fn shift_right(value: Int, count: Int) Int:

# Shifts bits toward the low end, filling with zeros (JavaScript `>>>`); `count` must be 0 through 63 or the call faults.
export fn shift_right_unsigned(value: Int, count: Int) Int:

# Rotates the 64-bit pattern toward the high end; any `count` is reduced modulo 64.
export fn rotate_left(value: Int, count: Int) Int:

# Rotates the 64-bit pattern toward the low end; any `count` is reduced modulo 64.
export fn rotate_right(value: Int, count: Int) Int:

# Counts the set bits in the 64-bit pattern.
export fn count_ones(value: Int) Int:

# Counts the zero bits above the highest set bit; zero has 64.
export fn leading_zeros(value: Int) Int:

# Counts the zero bits below the lowest set bit; zero has 64.
export fn trailing_zeros(value: Int) Int:

# Adds with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_add(left: Int, right: Int) Int:

# Subtracts with two's-complement wraparound instead of faulting on overflow.
export fn wrapping_subtract(left: Int, right: Int) Int:

# Multiplies with two's-complement wraparound instead of faulting on overflow (JavaScript `Math.imul` at 64 bits).
export fn wrapping_multiply(left: Int, right: Int) Int:

# Errors returned while parsing or converting arbitrary-precision integers.
export type BigIntError:
    # The radix is outside 2 through 36, `max_digits` is negative, or a division or remainder has a zero divisor.
    case InvalidInput
    # The text is not an optionally signed integer made only of digits valid in the radix.
    case InvalidData
    # The text exceeds `max_digits` after excluding at most one leading sign; this check precedes syntax validation.
    case LimitExceeded

# An arbitrary-precision signed integer with explicit arithmetic operations.
export type BigInt:

impl BigInt:
    # Returns the exact sum; arbitrary precision means it cannot overflow.
    fn add(other: BigInt) BigInt:

    # Returns the exact difference `self - other`; it cannot overflow.
    fn subtract(other: BigInt) BigInt:

    # Returns the exact product; it cannot overflow, though very large operands take proportionally longer.
    fn multiply(other: BigInt) BigInt:

    # Returns the quotient truncated toward zero, so -7 divided by 2 is -3.
    # A zero divisor returns InvalidInput.
    fn divide(other: BigInt) Result[BigInt, BigIntError]:

    # Returns the remainder whose sign follows the dividend, so -7 remainder 2 is -1.
    # A zero divisor returns InvalidInput.
    fn remainder(other: BigInt) Result[BigInt, BigIntError]:

    # Returns -1 when this value is less than `other`, 0 when equal, and 1 when greater.
    fn compare(other: BigInt) Int:

    # Returns the bitwise AND using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    fn bit_and(other: BigInt) BigInt:

    # Returns the bitwise OR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    fn bit_or(other: BigInt) BigInt:

    # Returns the bitwise XOR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.
    fn bit_xor(other: BigInt) BigInt:

    # Returns the bitwise complement using infinite-width two's-complement semantics, so `bit_not(x)` equals `-x - 1`.
    fn bit_not() BigInt:

    # Returns the value with its sign flipped.
    fn negate() BigInt:

    # Returns the absolute value, which is never negative.
    fn abs() BigInt:

    # Returns -1, 0 or 1 as the value is negative, zero or positive.
    fn sign() Int:

    # Raises to a nonnegative `exponent`. A negative exponent returns InvalidInput, and a result above 16777216 bits returns LimitExceeded.
    fn pow(exponent: Int) Result[BigInt, BigIntError]:

    # Shifts left by `count` bits, multiplying by two to that power. A negative count returns InvalidInput, and a result above 16777216 bits returns LimitExceeded.
    fn shift_left(count: Int) Result[BigInt, BigIntError]:

    # Shifts right by `count` bits with floor semantics for negatives, so -5 shifted by 1 is -3. A negative count returns InvalidInput.
    fn shift_right(count: Int) Result[BigInt, BigIntError]:

    # Converts to the nearest Float, or infinity of the same sign when the magnitude exceeds the Float range.
    fn to_float() Float:

    # Returns the value as an Int when it fits in the platform's Int, or none when it is outside that range.
    fn to_int() Optional[Int]:

    # Formats the value in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string_radix(radix: Int) String:

# Converts a machine-sized integer without loss.
export fn from_int(value: Int) BigInt:

# Parses a base-2 through base-36 integer. `max_digits` bounds work when supplied.
export fn parse(
    text: String,
    radix: Int,
    max_digits: Optional[Int] = none
) Result[BigInt, BigIntError]:

impl Error for BigIntError:
    # Returns the fixed diagnostic `big integer: <reason>`, such as `big integer: invalid input`, without echoing the input text.
    fn message() String:
