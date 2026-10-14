+++
title = "bigint"
+++

# @std/bigint.ms

Import each required symbol with `import Name from "@std/bigint.ms"`.

## BigInt {data-api-kind="Native type"}

An arbitrary-precision signed integer with explicit arithmetic operations.

```manuscript
type BigInt:
    fn add(right: BigInt) -> BigInt:
    fn subtract(right: BigInt) -> BigInt:
    fn multiply(right: BigInt) -> BigInt:
    fn divide(right: BigInt) -> Result[BigInt, BigIntError]:
    fn remainder(right: BigInt) -> Result[BigInt, BigIntError]:
    fn compare(right: BigInt) -> Int:
    fn bit_and(right: BigInt) -> BigInt:
    fn bit_or(right: BigInt) -> BigInt:
    fn bit_xor(right: BigInt) -> BigInt:
    fn negate() -> BigInt:
    fn abs() -> BigInt:
    fn bit_not() -> BigInt:
    fn pow(exponent: Int, max_bits: Optional[Int] = none) -> Result[BigInt, BigIntError]:
    fn shift_left(count: Int, max_bits: Optional[Int] = none) -> Result[BigInt, BigIntError]:
    fn shift_right(count: Int) -> Result[BigInt, BigIntError]:
    fn to_int() -> Optional[Int]:
    fn to_string(radix: Int) -> String:
```

### BigInt.abs

Returns the nonnegative magnitude without changing this value.

```manuscript
fn abs() -> BigInt:
```

### BigInt.bit_not

Complements every bit using an infinite signed two's-complement representation.

```manuscript
fn bit_not() -> BigInt:
```

### BigInt.negate

Returns the additive inverse without changing this value.

```manuscript
fn negate() -> BigInt:
```

### BigInt.pow

Raises this value to a nonnegative exponent; zero to the zero power is one.
Negative exponent or max_bits returns InvalidInput; output beyond max_bits returns LimitExceeded.
Omitted/none max_bits adds no caller budget; a native ceiling of 2^28 magnitude bits still applies.

```manuscript
fn pow(exponent: Int, max_bits: Optional[Int] = none) -> Result[BigInt, BigIntError]:
```

### BigInt.shift_left

Shifts left by count bits, preserving the sign and leaving this value unchanged.
Negative count or max_bits returns InvalidInput; output beyond max_bits returns LimitExceeded.
Omitted/none max_bits adds no caller budget; a native ceiling of 2^28 magnitude bits still applies.

```manuscript
fn shift_left(count: Int, max_bits: Optional[Int] = none) -> Result[BigInt, BigIntError]:
```

### BigInt.shift_right

Shifts right arithmetically; discarded bits round a negative value toward negative infinity.
A negative count returns InvalidInput; arbitrarily large counts yield zero or negative one.

```manuscript
fn shift_right(count: Int) -> Result[BigInt, BigIntError]:
```

## BigIntError {data-api-kind="Alternative"}

Errors returned for invalid arithmetic requests, malformed digits, or excessive integer growth.

```manuscript
type BigIntError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for BigIntError:
    fn message() -> String:
```

## from_int {data-api-kind="Function"}

Converts a machine-sized integer without loss.

```manuscript
fn from_int(value: Int) -> BigInt:
```

## parse {data-api-kind="Function"}

Parses a base-2 through base-36 integer. `max_digits` bounds work when supplied.

```manuscript
fn parse(text: String, radix: Int, max_digits: Optional[Int] = none) -> Result[BigInt, BigIntError]:
```

