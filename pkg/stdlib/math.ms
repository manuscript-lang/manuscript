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

# Returns the floating-point remainder of `left / right` with the sign of `left`, like Int `%` (C `fmod`), not the IEEE round-to-nearest remainder: `remainder(5.0, 3.0)` is 2.0. A zero `right` or infinite `left` gives NaN; an infinite `right` returns `left`.
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
