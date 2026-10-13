# Canonical standard-library declarations. Implementations are native.

# Errors returned while parsing or converting arbitrary-precision integers.
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
