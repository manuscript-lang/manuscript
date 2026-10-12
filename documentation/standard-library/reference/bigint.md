+++
title = "bigint"
+++

# @std/bigint.ms

Import each required symbol with `import Name from "@std/bigint.ms"`.

## BigInt {data-api-kind="Native type"}

```manuscript
type BigInt:
    fn add(right: BigInt) -> BigInt
    fn subtract(right: BigInt) -> BigInt
    fn multiply(right: BigInt) -> BigInt
    fn divide(right: BigInt) -> Result[BigInt, BigIntError]
    fn remainder(right: BigInt) -> Result[BigInt, BigIntError]
    fn compare(right: BigInt) -> Int
    fn bit_and(right: BigInt) -> BigInt
    fn bit_or(right: BigInt) -> BigInt
    fn bit_xor(right: BigInt) -> BigInt
    fn to_int() -> Optional[Int]
    fn to_string(radix: Int) -> String
```

## BigIntError {data-api-kind="Alternative"}

```manuscript
type BigIntError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for BigIntError:
    fn message() -> String
```

## from_int {data-api-kind="Function"}

```manuscript
fn from_int(value: Int) -> BigInt
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String, radix: Int, max_digits: Optional[Int] = none) -> Result[BigInt, BigIntError]
```

