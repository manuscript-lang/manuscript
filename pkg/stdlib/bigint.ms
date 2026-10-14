# Canonical standard-library declarations. Implementations are native.

# Errors returned while parsing or converting arbitrary-precision integers.
export type BigIntError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# An arbitrary-precision signed integer with explicit arithmetic operations.
export type BigInt:
    fn add(other: BigInt) -> BigInt:
    fn subtract(other: BigInt) -> BigInt:
    fn multiply(other: BigInt) -> BigInt:
    fn divide(other: BigInt) -> Result[BigInt, BigIntError]:
    fn remainder(other: BigInt) -> Result[BigInt, BigIntError]:
    fn compare(other: BigInt) -> Int:
    fn bit_and(other: BigInt) -> BigInt:
    fn bit_or(other: BigInt) -> BigInt:
    fn bit_xor(other: BigInt) -> BigInt:
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
