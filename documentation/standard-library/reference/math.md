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

## asin {data-api-kind="Function"}

Returns the inverse sine in radians.

```manuscript
fn asin(value: Float) -> Float:
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

## ceil {data-api-kind="Function"}

Rounds upward to the nearest whole number.

```manuscript
fn ceil(value: Float) -> Float:
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

## min {data-api-kind="Function"}

Returns the lesser of two floating-point values.

```manuscript
fn min(left: Float, right: Float) -> Float:
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

## remainder {data-api-kind="Function"}

Returns the floating-point remainder after division.

```manuscript
fn remainder(left: Float, right: Float) -> Float:
```

## round {data-api-kind="Function"}

Rounds to the nearest whole number, with ties toward positive infinity.

```manuscript
fn round(value: Float) -> Float:
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

