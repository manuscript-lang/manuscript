+++
title = "math"
+++

# @std/math.ms

Import each required symbol with `import Name from "@std/math.ms"`.

## abs {data-api-kind="Function"}

Returns the absolute value of a floating-point number.

```manuscript
fn abs(value: Float) -> Float:
```

## abs_int {data-api-kind="Function"}

Returns the absolute value of an integer.

```manuscript
fn abs_int(value: Int) -> Int:
```

## acos {data-api-kind="Function"}

Returns the inverse cosine in radians.

```manuscript
fn acos(value: Float) -> Float:
```

## acosh {data-api-kind="Function"}

Returns the inverse hyperbolic cosine; values below one produce NaN.

```manuscript
fn acosh(value: Float) -> Float:
```

## asin {data-api-kind="Function"}

Returns the inverse sine in radians.

```manuscript
fn asin(value: Float) -> Float:
```

## asinh {data-api-kind="Function"}

Returns the inverse hyperbolic sine; infinities and NaN propagate.

```manuscript
fn asinh(value: Float) -> Float:
```

## atan {data-api-kind="Function"}

Returns the inverse tangent in radians.

```manuscript
fn atan(value: Float) -> Float:
```

## atan2 {data-api-kind="Function"}

Returns the angle in radians for `(x, y)`, preserving its quadrant.

```manuscript
fn atan2(y: Float, x: Float) -> Float:
```

## atanh {data-api-kind="Function"}

Returns the inverse hyperbolic tangent; values outside [-1, 1] produce NaN.
At -1 and 1 the result is negative and positive infinity respectively.

```manuscript
fn atanh(value: Float) -> Float:
```

## cbrt {data-api-kind="Function"}

Returns the real cube root, including for negative values.

```manuscript
fn cbrt(value: Float) -> Float:
```

## ceil {data-api-kind="Function"}

Rounds upward to the nearest whole number.

```manuscript
fn ceil(value: Float) -> Float:
```

## ceil_to_int {data-api-kind="Function"}

Rounds upward and converts to Int; nonfinite or out-of-range results return none.

```manuscript
fn ceil_to_int(value: Float) -> Optional[Int]:
```

## clamp {data-api-kind="Function"}

Clamps a value to the inclusive bounds; NaN in any argument produces NaN.
Reversed bounds fault; supply minimum <= maximum.

```manuscript
fn clamp(value: Float, minimum: Float, maximum: Float) -> Float:
```

## clamp_int {data-api-kind="Function"}

Clamps an integer to the inclusive bounds without converting to Float.
Reversed bounds fault; supply minimum <= maximum.

```manuscript
fn clamp_int(value: Int, minimum: Int, maximum: Int) -> Int:
```

## cos {data-api-kind="Function"}

Returns the cosine of an angle in radians.

```manuscript
fn cos(value: Float) -> Float:
```

## cosh {data-api-kind="Function"}

Returns the hyperbolic cosine.

```manuscript
fn cosh(value: Float) -> Float:
```

## e {data-api-kind="Function"}

Returns Euler's number, the base of natural logarithms.

```manuscript
fn e() -> Float:
```

## exp {data-api-kind="Function"}

Returns e raised to `value`.

```manuscript
fn exp(value: Float) -> Float:
```

## floor {data-api-kind="Function"}

Rounds downward to the nearest whole number.

```manuscript
fn floor(value: Float) -> Float:
```

## floor_to_int {data-api-kind="Function"}

Rounds downward and converts to Int; nonfinite or out-of-range results return none.

```manuscript
fn floor_to_int(value: Float) -> Optional[Int]:
```

## hypot {data-api-kind="Function"}

Returns the length of the hypotenuse for sides `left` and `right`.

```manuscript
fn hypot(left: Float, right: Float) -> Float:
```

## log {data-api-kind="Function"}

Returns the natural logarithm.

```manuscript
fn log(value: Float) -> Float:
```

## log10 {data-api-kind="Function"}

Returns the base-10 logarithm.

```manuscript
fn log10(value: Float) -> Float:
```

## log2 {data-api-kind="Function"}

Returns the base-2 logarithm.

```manuscript
fn log2(value: Float) -> Float:
```

## max {data-api-kind="Function"}

Returns the greater of two floating-point values.

```manuscript
fn max(left: Float, right: Float) -> Float:
```

## max_int {data-api-kind="Function"}

Returns the greater signed 64-bit integer without converting to Float.

```manuscript
fn max_int(left: Int, right: Int) -> Int:
```

## min {data-api-kind="Function"}

Returns the lesser of two floating-point values.

```manuscript
fn min(left: Float, right: Float) -> Float:
```

## min_int {data-api-kind="Function"}

Returns the lesser signed 64-bit integer without converting to Float.

```manuscript
fn min_int(left: Int, right: Int) -> Int:
```

## pi {data-api-kind="Function"}

Returns π, the ratio of a circle's circumference to its diameter.

```manuscript
fn pi() -> Float:
```

## pow {data-api-kind="Function"}

Returns `base` raised to `exponent`.

```manuscript
fn pow(base: Float, exponent: Float) -> Float:
```

## pow_int {data-api-kind="Function"}

Raises an integer to a nonnegative integer exponent; zero to the zero power is one.
Negative exponents return InvalidInput; signed 64-bit overflow returns OutOfRange.

```manuscript
fn pow_int(base: Int, exponent: Int) -> Result[Int, NumberError]:
```

## remainder {data-api-kind="Function"}

Returns the floating-point remainder after division.

```manuscript
fn remainder(left: Float, right: Float) -> Float:
```

## round {data-api-kind="Function"}

Rounds to the nearest whole number, with half values toward positive infinity.

```manuscript
fn round(value: Float) -> Float:
```

## round_to_int {data-api-kind="Function"}

Rounds to the nearest integer with ties toward positive infinity, as round does.
Returns none for nonfinite values or a rounded value outside signed 64-bit range.

```manuscript
fn round_to_int(value: Float) -> Optional[Int]:
```

## sign {data-api-kind="Function"}

Returns -1, 0, or 1 for the sign; preserves signed zero and propagates NaN.

```manuscript
fn sign(value: Float) -> Float:
```

## sign_int {data-api-kind="Function"}

Returns -1, 0, or 1 for the sign of a signed 64-bit integer.

```manuscript
fn sign_int(value: Int) -> Int:
```

## sin {data-api-kind="Function"}

Returns the sine of an angle in radians.

```manuscript
fn sin(value: Float) -> Float:
```

## sinh {data-api-kind="Function"}

Returns the hyperbolic sine.

```manuscript
fn sinh(value: Float) -> Float:
```

## sqrt {data-api-kind="Function"}

Returns the non-negative square root.

```manuscript
fn sqrt(value: Float) -> Float:
```

## sum_float {data-api-kind="Function"}

Adds floating-point values in order using IEEE arithmetic; an empty list sums to zero.
NaN and infinity follow ordinary Float addition; input is unchanged.

```manuscript
fn sum_float(values: List[Float]) -> Float:
```

## sum_int {data-api-kind="Function"}

Adds integer values in order; an empty list sums to zero.
Returns OutOfRange if any running total leaves the signed 64-bit range; input is unchanged.

```manuscript
fn sum_int(values: List[Int]) -> Result[Int, NumberError]:
```

## tan {data-api-kind="Function"}

Returns the tangent of an angle in radians.

```manuscript
fn tan(value: Float) -> Float:
```

## tanh {data-api-kind="Function"}

Returns the hyperbolic tangent.

```manuscript
fn tanh(value: Float) -> Float:
```

## truncate {data-api-kind="Function"}

Truncates a value toward zero.

```manuscript
fn truncate(value: Float) -> Float:
```

