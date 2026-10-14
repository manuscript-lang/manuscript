+++
title = "bigint"
+++

# @std/bigint.ms

Import each required symbol with `import Name from "@std/bigint.ms"`.

## BigInt {data-api-kind="Native type"}

An arbitrary-precision signed integer with explicit arithmetic operations.

```manuscript
type BigInt:
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

