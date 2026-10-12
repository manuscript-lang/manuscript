+++
title = "Numbers and mathematics"
weight = 50
+++

# Numbers and mathematics

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use math for floating-point calculations, numbers for text conversion, and bigint when values exceed the Int range. Numeric conversions are explicit. Read the behavior sections before depending on rounding or overflow results.

## `@std/math.ms`

```text
fn abs(value: Float) -> Float
fn abs_int(value: Int) -> Int
fn acos(value: Float) -> Float
fn asin(value: Float) -> Float
fn atan(value: Float) -> Float
fn atan2(y: Float, x: Float) -> Float
fn ceil(value: Float) -> Float
fn cos(value: Float) -> Float
fn cosh(value: Float) -> Float
fn e() -> Float
fn exp(value: Float) -> Float
fn floor(value: Float) -> Float
fn hypot(left: Float, right: Float) -> Float
fn is_finite(value: Float) -> Bool
fn is_nan(value: Float) -> Bool
fn log(value: Float) -> Float
fn log10(value: Float) -> Float
fn log2(value: Float) -> Float
fn max(left: Float, right: Float) -> Float
fn min(left: Float, right: Float) -> Float
fn pi() -> Float
fn pow(base: Float, exponent: Float) -> Float
fn remainder(left: Float, right: Float) -> Float
fn round(value: Float) -> Float
fn sin(value: Float) -> Float
fn sinh(value: Float) -> Float
fn sqrt(value: Float) -> Float
fn tan(value: Float) -> Float
fn tanh(value: Float) -> Float
fn truncate(value: Float) -> Float
```

## `@std/numbers.ms`

```text
fn format_float(value: Float) -> String
fn format_int(value: Int, radix: Int) -> String
fn parse_float(text: String) -> Result[Float, LibraryError]
fn parse_int(text: String, radix: Int) -> Result[Int, LibraryError]
```

## `@std/bigint.ms`

```text
fn add(left: BigInt, right: BigInt) -> BigInt
fn bit_and(left: BigInt, right: BigInt) -> BigInt
fn bit_or(left: BigInt, right: BigInt) -> BigInt
fn bit_xor(left: BigInt, right: BigInt) -> BigInt
fn compare(left: BigInt, right: BigInt) -> Int
fn divide(left: BigInt, right: BigInt) -> Result[BigInt, LibraryError]
fn format(value: BigInt, radix: Int) -> String
fn from_int(value: Int) -> BigInt
fn multiply(left: BigInt, right: BigInt) -> BigInt
fn parse(text: String, radix: Int, max_digits: Int) -> Result[BigInt, LibraryError]
fn remainder(left: BigInt, right: BigInt) -> Result[BigInt, LibraryError]
fn subtract(left: BigInt, right: BigInt) -> BigInt
fn to_int(value: BigInt) -> Optional[Int]
```

## Floating-point behavior

Math functions use IEEE binary64 and Go's domain and overflow rules. An invalid Float domain yields NaN; overflow can yield infinity. The last bits of transcendental results may differ across targets, so tests should use tolerances.

`round` uses ties-to-even. `min` and `max` propagate NaN and preserve signed-zero conventions. `abs_int(MinInt64)` faults because the positive result cannot fit in an `Int`. `pi()` and `e()` are ordinary zero-argument functions.

## Parsing and formatting numbers

Integer radices are 2–36. Input may have a sign and ASCII digits or letters. Parsing consumes the whole input and rejects prefixes, whitespace, and separators. An invalid radix returns `InvalidInput` when parsing and faults when formatting. An integer outside the `Int` range returns `OutOfRange`.

Float parsing accepts signed decimal digits with an optional fraction or exponent. A present decimal point needs at least one digit on each side. It also accepts `NaN`, `Infinity`, and `-Infinity`. Finite syntax that overflows binary64 returns `OutOfRange`. Formatting uses the existing round-trip Float representation.

## Arbitrary-precision integers

`BigInt` is opaque, immutable, shareable, and comparable for equality. Create it with `from_int` or `parse`; there is no source constructor, literal, arithmetic operator, or hashing guarantee. Arithmetic functions leave both operands unchanged. Conversion between `Int` and `BigInt` is explicit.

| Operation | Behavior |
| --- | --- |
| Parse | `max_digits` is positive and counts digits excluding the optional sign. |
| Divide | Truncates toward zero; division by zero returns `InvalidInput`. |
| Remainder | Has the dividend's sign; a zero divisor returns `InvalidInput`. |
| Compare | Returns -1, 0, or 1. |
| Convert to Int | Returns `none` outside the signed 64-bit range. |
| Bit operations | Use mathematical two's-complement semantics. |

A very large native arithmetic operation can delay cancellation until it returns. Bound input magnitudes where that matters. Decimal keeps its existing 34-digit contract; extended Decimal parse and format APIs remain future work.
