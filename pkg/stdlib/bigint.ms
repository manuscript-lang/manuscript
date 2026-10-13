# Canonical standard-library declarations. Implementations are native.

# Errors returned for invalid arithmetic requests, malformed digits, or excessive integer growth.
export type BigIntError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# An arbitrary-precision signed integer with explicit arithmetic operations.
export type BigInt:
    fn add(right: BigInt) -> BigInt:
    fn subtract(right: BigInt) -> BigInt:
    fn multiply(right: BigInt) -> BigInt:
    fn divide(right: BigInt) -> Result[BigInt, BigIntError]:
    fn remainder(right: BigInt) -> Result[BigInt, BigIntError]:
    fn compare(right: BigInt) -> Int:
    fn bit_and(right: BigInt) -> BigInt:
    fn bit_or(right: BigInt) -> BigInt:
    fn bit_xor(right: BigInt) -> BigInt:
    # Returns the additive inverse without changing this value.
    fn negate() -> BigInt:
    # Returns the nonnegative magnitude without changing this value.
    fn abs() -> BigInt:
    # Complements every bit using an infinite signed two's-complement representation.
    fn bit_not() -> BigInt:
    # Raises this value to a nonnegative exponent; zero to the zero power is one.
    # Negative exponent or max_bits returns InvalidInput; output beyond max_bits returns LimitExceeded.
    # Omitted/none max_bits adds no caller budget; a native ceiling of 2^28 magnitude bits still applies.
    fn pow(exponent: Int, max_bits: Optional[Int] = none) -> Result[BigInt, BigIntError]:
    # Shifts left by count bits, preserving the sign and leaving this value unchanged.
    # Negative count or max_bits returns InvalidInput; output beyond max_bits returns LimitExceeded.
    # Omitted/none max_bits adds no caller budget; a native ceiling of 2^28 magnitude bits still applies.
    fn shift_left(
        count: Int,
        max_bits: Optional[Int] = none
    ) -> Result[BigInt, BigIntError]:
    # Shifts right arithmetically; discarded bits round a negative value toward negative infinity.
    # A negative count returns InvalidInput; arbitrarily large counts yield zero or negative one.
    fn shift_right(count: Int) -> Result[BigInt, BigIntError]:
    fn to_int() -> Optional[Int]:
    fn to_string(radix: Int) -> String:

# Converts a machine-sized integer without loss.
export fn from_int(value: Int) -> BigInt:

# Parses a base-2 through base-36 integer. `max_digits` bounds work when supplied.
export fn parse(
    text: String,
    radix: Int,
    max_digits: Optional[Int] = none
) -> Result[BigInt, BigIntError]:

impl Error for BigIntError:
    fn message() -> String:
