# Canonical standard-library declarations. Implementations are native.

# Returns the absolute value of a floating-point number.
export fn abs(value: Float) -> Float:

# Returns the absolute value of an integer.
export fn abs_int(value: Int) -> Int:

# Returns the inverse cosine in radians.
export fn acos(value: Float) -> Float:

# Returns the inverse sine in radians.
export fn asin(value: Float) -> Float:

# Returns the inverse tangent in radians.
export fn atan(value: Float) -> Float:

# Returns the angle in radians for `(x, y)`, preserving its quadrant.
export fn atan2(y: Float, x: Float) -> Float:

# Rounds upward to the nearest whole number.
export fn ceil(value: Float) -> Float:

# Returns the cosine of an angle in radians.
export fn cos(value: Float) -> Float:

# Returns the hyperbolic cosine.
export fn cosh(value: Float) -> Float:

# Returns Euler's number, the base of natural logarithms.
export fn e() -> Float:

# Returns e raised to `value`.
export fn exp(value: Float) -> Float:

# Rounds downward to the nearest whole number.
export fn floor(value: Float) -> Float:

# Returns the length of the hypotenuse for sides `left` and `right`.
export fn hypot(left: Float, right: Float) -> Float:

# Returns the natural logarithm.
export fn log(value: Float) -> Float:

# Returns the base-10 logarithm.
export fn log10(value: Float) -> Float:

# Returns the base-2 logarithm.
export fn log2(value: Float) -> Float:

# Returns the greater of two floating-point values.
export fn max(left: Float, right: Float) -> Float:

# Returns the lesser of two floating-point values.
export fn min(left: Float, right: Float) -> Float:

# Returns π, the ratio of a circle's circumference to its diameter.
export fn pi() -> Float:

# Returns `base` raised to `exponent`.
export fn pow(base: Float, exponent: Float) -> Float:

# Returns the floating-point remainder after division.
export fn remainder(left: Float, right: Float) -> Float:

# Rounds to the nearest whole number, with ties toward positive infinity.
export fn round(value: Float) -> Float:

# Returns the sine of an angle in radians.
export fn sin(value: Float) -> Float:

# Returns the hyperbolic sine.
export fn sinh(value: Float) -> Float:

# Returns the non-negative square root.
export fn sqrt(value: Float) -> Float:

# Returns the tangent of an angle in radians.
export fn tan(value: Float) -> Float:

# Returns the hyperbolic tangent.
export fn tanh(value: Float) -> Float:

# Truncates a value toward zero.
export fn truncate(value: Float) -> Float:

# documentation documentation/standard-library/math.md
# +++
# title = "Numbers and mathematics"
# weight = 7
# +++
#
# # Numbers and mathematics
#
# API reference: [math](reference/math.md), [numbers](reference/numbers.md), [decimal](reference/decimal.md), [bigint](reference/bigint.md).
#
# Use math for floating-point calculations, numbers for text conversion, and bigint when values exceed the Int range. Numeric conversions are explicit. Read the behavior sections before depending on rounding or overflow results.
#
# ## Floating-point behavior
#
# Math functions use IEEE binary64 arithmetic. An invalid Float domain yields NaN; overflow can yield infinity. The last bits of transcendental results may differ across targets, so tests should use tolerances.
#
# `round` rounds to the nearest integer, with ties toward positive infinity: `round(1.5)` is `2.0`, and `round(-1.5)` is `-1.0`. It preserves negative zero for negative inputs that round to zero. `min` and `max` propagate NaN and preserve signed-zero conventions. `abs_int(MinInt64)` faults because the positive result cannot fit in an `Int`. `pi()` and `e()` are ordinary zero-argument functions.
#
# ## Parsing and formatting numbers
#
# Integer radices are 2–36. Input may have a sign and ASCII digits or letters. Parsing consumes the whole input and rejects prefixes, whitespace, and separators. An invalid radix returns `InvalidInput` when parsing and faults when formatting. An integer outside the `Int` range returns `OutOfRange`.
#
# Float parsing accepts signed decimal digits with an optional fraction or exponent. A present decimal point needs at least one digit on each side. It also accepts `NaN`, `Infinity`, and `-Infinity`. Finite syntax that overflows binary64 returns `OutOfRange`. Formatting uses the existing round-trip Float representation.
#
# | Float receiver operation | Behavior |
# | --- | --- |
# | `to_fixed(digits:)` | Request 0–100 fractional digits; for magnitudes at least 1e21, use the ordinary round-trip representation instead. |
# | `to_exponential(digits:)` | Request 0–100 fractional digits in scientific notation, with an explicit exponent sign. |
# | `to_precision(precision:)` | Request 1–100 significant digits. Use plain notation when the first significant digit's exponent is at least -6 and below `precision`; otherwise use scientific notation. |
# | `is_nan` | True exactly for NaN. |
# | `is_finite` | False for NaN and either infinity. |
#
# The three precision-formatting operations return `Result[String, NumberError]`; an out-of-range digit count returns `NumberError.InvalidInput`. They round the stored binary64 value with ties to even, preserve requested trailing zeros and signed zero, and format nonfinite values as `NaN`, `Infinity`, or `-Infinity` after validating the count. For example, `1.5.to_fixed(digits: 3)` returns `ok("1.500")` and `1.5.to_exponential(digits: 2)` returns `ok("1.50e+0")`. These methods differ from the shortest representation used by [interpolation and `toString()`](../core-language/basics/text-and-bytes.md#deterministic-formatting).
#
# ## Arbitrary-precision integers
#
# `BigInt` is opaque, immutable, and comparable for equality. Create it with `from_int` or `parse`; there is no source constructor, literal, arithmetic operator, or hashing guarantee. Arithmetic functions leave both operands unchanged. Conversion between `Int` and `BigInt` is explicit.
#
# | Operation | Behavior |
# | --- | --- |
# | Parse | `max_digits` is positive and counts digits excluding the optional sign. |
# | Divide | Truncates toward zero; division by zero returns `InvalidInput`. |
# | Remainder | Has the dividend's sign; a zero divisor returns `InvalidInput`. |
# | Compare | Returns -1, 0, or 1. |
# | Convert to Int | Returns `none` outside the signed 64-bit range. |
# | Bit operations | Use mathematical two's-complement semantics. |
#
# A very large native arithmetic operation can delay cancellation until it returns. Bound input magnitudes where that matters. Decimal keeps its [34-digit arithmetic and explicit scale rounding](../core-language/basics/numbers-and-booleans.md#decimal) contract. Its `to_fixed` method formats exact decimal values with stable trailing zeros. Decimal text parsing remains unsupported.
# end-documentation
