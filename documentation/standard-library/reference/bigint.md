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
    fn to_int() -> Optional[Int]:
    fn to_string(radix: Int) -> String:
```

### BigInt.add

Returns the exact sum; arbitrary precision means it cannot overflow.

```manuscript
fn add(right: BigInt) -> BigInt:
```

### BigInt.bit_and

Returns the bitwise AND using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.

```manuscript
fn bit_and(right: BigInt) -> BigInt:
```

### BigInt.bit_or

Returns the bitwise OR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.

```manuscript
fn bit_or(right: BigInt) -> BigInt:
```

### BigInt.bit_xor

Returns the bitwise XOR using infinite-width two's-complement semantics, so negative operands behave as if sign-extended.

```manuscript
fn bit_xor(right: BigInt) -> BigInt:
```

### BigInt.compare

Returns -1 when this value is less than `right`, 0 when equal, and 1 when greater.

```manuscript
fn compare(right: BigInt) -> Int:
```

### BigInt.divide

Returns the quotient truncated toward zero, so -7 divided by 2 is -3.
A zero divisor returns InvalidInput.

```manuscript
fn divide(right: BigInt) -> Result[BigInt, BigIntError]:
```

### BigInt.multiply

Returns the exact product; it cannot overflow, though very large operands take proportionally longer.

```manuscript
fn multiply(right: BigInt) -> BigInt:
```

### BigInt.remainder

Returns the remainder whose sign follows the dividend, so -7 remainder 2 is -1.
A zero divisor returns InvalidInput.

```manuscript
fn remainder(right: BigInt) -> Result[BigInt, BigIntError]:
```

### BigInt.subtract

Returns the exact difference `self - right`; it cannot overflow.

```manuscript
fn subtract(right: BigInt) -> BigInt:
```

### BigInt.to_int

Returns the value as an Int when it fits in signed 64 bits, or none when it is outside that range.

```manuscript
fn to_int() -> Optional[Int]:
```

### BigInt.to_string

Formats the value in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
A radix outside 2 through 36 is a programming fault.

```manuscript
fn to_string(radix: Int) -> String:
```

## BigIntError {data-api-kind="Alternative"}

Errors returned while parsing or converting arbitrary-precision integers.

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

### BigIntError.InvalidData

The text is not an optionally signed integer made only of digits valid in the radix.

```manuscript
case InvalidData
```

### BigIntError.InvalidInput

The radix is outside 2 through 36, `max_digits` is negative, or a division or remainder has a zero divisor.

```manuscript
case InvalidInput
```

### BigIntError.LimitExceeded

The text has more digits than `max_digits`; the sign is not counted, and this check precedes syntax validation.

```manuscript
case LimitExceeded
```

### BigIntError.Error.message

Returns the fixed diagnostic `big integer: <reason>`, such as `big integer: invalid input`, without echoing the input text.

```manuscript
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

