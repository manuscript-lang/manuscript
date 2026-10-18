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
