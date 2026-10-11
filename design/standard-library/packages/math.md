+++
title = "Numbers and mathematics"
weight = 50
+++

# Numbers and mathematics

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

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

## Behavior

Math functions use IEEE binary64 and Go math domain/overflow behavior: invalid Float domains yield NaN and overflow can produce infinity. Round is ties-to-even; min/max propagate NaN and preserve signed-zero conventions. Abs_int(MinInt64) faults. Pi/e are zero-argument library functions, not ambient constants. Transcendental last bits may vary by target; tests should use tolerances.

Integer radices are 2–36, with optional sign and ASCII digits/letters only; parse consumes all input and rejects prefixes, whitespace and separators. Invalid radix returns InvalidInput for parsing and faults for formatting. Out-of-range Int returns OutOfRange. Float parsing accepts signed decimal digits with optional fraction/exponent (at least one digit on each side of a present decimal point), plus NaN/Infinity/-Infinity. Finite syntax overflowing binary64 returns OutOfRange. Formatting uses existing round-trip Float rendering.

BigInt is opaque, immutable, shareable and equal, with no source constructor, literals, arithmetic operators, or hashing guarantee. Use from_int/parse and named functions. Max_digits is positive and includes digits excluding the optional sign. Division truncates toward zero; remainder follows the dividend sign. Division by zero returns InvalidInput. Compare returns -1/0/1. To_int returns none outside signed 64-bit range. Bit operations use mathematical two's-complement semantics. Arithmetic never mutates either operand. Int and BigInt never convert implicitly. Very large single native arithmetic operations may delay cancellation until they return; callers should bound input magnitudes. Decimal retains its existing 34-digit contract; extended Decimal parse/format APIs remain deferred.
