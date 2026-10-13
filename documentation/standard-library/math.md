+++
title = "Numbers and mathematics"
weight = 7
+++

# Numbers and mathematics

API reference: [math](reference/math.md), [numbers](reference/numbers.md), [bigint](reference/bigint.md).

Use math for floating-point calculations, numbers for text conversion, and bigint when values exceed the Int range. Numeric conversions are explicit. Read the behavior sections before depending on rounding or overflow results.

## Floating-point behavior

Math functions use IEEE binary64 arithmetic. An invalid Float domain yields NaN; overflow can yield infinity. The last bits of transcendental results may differ across targets, so tests should use tolerances.

`round` rounds to the nearest integer, with ties toward positive infinity: `round(1.5)` is `2.0`, and `round(-1.5)` is `-1.0`. It preserves negative zero for negative inputs that round to zero. `min` and `max` propagate NaN and preserve signed-zero conventions. `abs_int(MinInt64)` faults because the positive result cannot fit in an `Int`. `pi()` and `e()` are ordinary zero-argument functions.

## Parsing and formatting numbers

Integer radices are 2–36. Input may have a sign and ASCII digits or letters. Parsing consumes the whole input and rejects prefixes, whitespace, and separators. An invalid radix returns `InvalidInput` when parsing and faults when formatting. An integer outside the `Int` range returns `OutOfRange`.

Float parsing accepts signed decimal digits with an optional fraction or exponent. A present decimal point needs at least one digit on each side. It also accepts `NaN`, `Infinity`, and `-Infinity`. Finite syntax that overflows binary64 returns `OutOfRange`. Formatting uses the existing round-trip Float representation.

## Arbitrary-precision integers

`BigInt` is opaque, immutable, and comparable for equality. Create it with `from_int` or `parse`; there is no source constructor, literal, arithmetic operator, or hashing guarantee. Arithmetic functions leave both operands unchanged. Conversion between `Int` and `BigInt` is explicit.

| Operation | Behavior |
| --- | --- |
| Parse | `max_digits` is positive and counts digits excluding the optional sign. |
| Divide | Truncates toward zero; division by zero returns `InvalidInput`. |
| Remainder | Has the dividend's sign; a zero divisor returns `InvalidInput`. |
| Compare | Returns -1, 0, or 1. |
| Convert to Int | Returns `none` outside the signed 64-bit range. |
| Bit operations | Use mathematical two's-complement semantics. |

A very large native arithmetic operation can delay cancellation until it returns. Bound input magnitudes where that matters. Decimal keeps its existing 34-digit contract; extended Decimal parse and format APIs remain future work.
