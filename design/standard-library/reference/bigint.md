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
    fn divide(right: BigInt) -> Result[BigInt, LibraryError]
    fn remainder(right: BigInt) -> Result[BigInt, LibraryError]
    fn compare(right: BigInt) -> Int
    fn bit_and(right: BigInt) -> BigInt
    fn bit_or(right: BigInt) -> BigInt
    fn bit_xor(right: BigInt) -> BigInt
    fn to_int() -> Optional[Int]
    fn to_string(radix: Int) -> String
```

## add {data-api-kind="Function"}

```manuscript
fn add(left: BigInt, right: BigInt) -> BigInt
```

## bit_and {data-api-kind="Function"}

```manuscript
fn bit_and(left: BigInt, right: BigInt) -> BigInt
```

## bit_or {data-api-kind="Function"}

```manuscript
fn bit_or(left: BigInt, right: BigInt) -> BigInt
```

## bit_xor {data-api-kind="Function"}

```manuscript
fn bit_xor(left: BigInt, right: BigInt) -> BigInt
```

## compare {data-api-kind="Function"}

```manuscript
fn compare(left: BigInt, right: BigInt) -> Int
```

## divide {data-api-kind="Function"}

```manuscript
fn divide(left: BigInt, right: BigInt) -> Result[BigInt, LibraryError]
```

## format {data-api-kind="Function"}

```manuscript
fn format(value: BigInt, radix: Int) -> String
```

## from_int {data-api-kind="Function"}

```manuscript
fn from_int(value: Int) -> BigInt
```

## multiply {data-api-kind="Function"}

```manuscript
fn multiply(left: BigInt, right: BigInt) -> BigInt
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String, radix: Int, max_digits: Int) -> Result[BigInt, LibraryError]
```

## remainder {data-api-kind="Function"}

```manuscript
fn remainder(left: BigInt, right: BigInt) -> Result[BigInt, LibraryError]
```

## subtract {data-api-kind="Function"}

```manuscript
fn subtract(left: BigInt, right: BigInt) -> BigInt
```

## to_int {data-api-kind="Function"}

```manuscript
fn to_int(value: BigInt) -> Optional[Int]
```

