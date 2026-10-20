# Returns the absolute value of a floating-point number.
export fn abs(value: Float) Float:

# Returns the absolute value of an integer.
export fn abs_int(value: Int) Int:

# Returns the inverse cosine in radians.
export fn acos(value: Float) Float:

# Returns the inverse sine in radians.
export fn asin(value: Float) Float:

# Returns the inverse tangent in radians.
export fn atan(value: Float) Float:

# Returns the angle in radians for `(x, y)`, preserving its quadrant.
export fn atan2(y: Float, x: Float) Float:

# Rounds upward to the nearest whole number.
export fn ceil(value: Float) Float:

# Returns the cosine of an angle in radians.
export fn cos(value: Float) Float:

# Returns the hyperbolic cosine.
export fn cosh(value: Float) Float:

# Returns Euler's number, the base of natural logarithms.
export fn e() Float:

# Returns e raised to `value`.
export fn exp(value: Float) Float:

# Rounds downward to the nearest whole number.
export fn floor(value: Float) Float:

# Returns the length of the hypotenuse for sides `left` and `right`.
export fn hypot(left: Float, right: Float) Float:

# Returns the natural logarithm.
export fn log(value: Float) Float:

# Returns the base-10 logarithm.
export fn log10(value: Float) Float:

# Returns the base-2 logarithm.
export fn log2(value: Float) Float:

# Returns the greater of two values, or `left` when they compare equal. Float orders NaN above every other value, so a NaN operand makes the result NaN.
export fn max[T: Comparable](left: T, right: T) T:

# Returns the lesser of two values, or `left` when they compare equal. Float orders NaN above every other value.
export fn min[T: Comparable](left: T, right: T) T:

# Returns the greatest of the values, keeping the first of equal ones, or none for an empty list. Float orders NaN above every other value.
export fn max_of[T: Comparable](values: List[T]) Optional[T]:

# Returns the least of the values, keeping the first of equal ones, or none for an empty list. Float orders NaN above every other value.
export fn min_of[T: Comparable](values: List[T]) Optional[T]:

# Returns π, the ratio of a circle's circumference to its diameter.
export fn pi() Float:

# Returns `base` raised to `exponent`.
export fn pow(base: Float, exponent: Float) Float:

# Returns the floating-point remainder of `left / right` with the sign of `left`, like Int `%` (C `fmod`), not the IEEE round-to-nearest remainder: `remainder(5.0, 3.0)` is 2.0. A zero `right` or infinite `left` gives NaN; an infinite `right` returns `left`.
export fn remainder(left: Float, right: Float) Float:

# Rounds to the nearest whole number, with ties toward positive infinity.
export fn round(value: Float) Float:

# Returns the sine of an angle in radians.
export fn sin(value: Float) Float:

# Returns the hyperbolic sine.
export fn sinh(value: Float) Float:

# Returns the non-negative square root.
export fn sqrt(value: Float) Float:

# Returns the tangent of an angle in radians.
export fn tan(value: Float) Float:

# Returns the hyperbolic tangent.
export fn tanh(value: Float) Float:

# Truncates a value toward zero.
export fn truncate(value: Float) Float:

# Returns the inverse hyperbolic cosine; values below 1.0 give NaN.
export fn acosh(value: Float) Float:

# Returns the inverse hyperbolic sine.
export fn asinh(value: Float) Float:

# Returns the inverse hyperbolic tangent; magnitudes above 1.0 give NaN.
export fn atanh(value: Float) Float:

# Returns the real cube root, which is defined for negative values.
export fn cbrt(value: Float) Float:

# Returns e raised to `value` minus one, accurate for values near zero.
export fn expm1(value: Float) Float:

# Returns the natural logarithm of one plus `value`, accurate for values near zero.
export fn log1p(value: Float) Float:

# Returns -1.0, 0.0 or 1.0 by sign, preserving signed zero and NaN.
export fn sign(value: Float) Float:

# Returns -1, 0 or 1 as the integer is negative, zero or positive.
export fn sign_int(value: Int) Int:

# Rounds to the nearest 32-bit floating-point value and widens it back to Float.
export fn to_float32(value: Float) Float:

# Reports whether the value is finite and has no fractional part.
export fn is_integer(value: Float) Bool:

# Reports whether the value is an integer within -(2^53 - 1) through 2^53 - 1, where Float represents integers exactly.
export fn is_safe_integer(value: Float) Bool:

# Returns positive infinity, the Float that exceeds every finite value; negate it for negative infinity.
export fn infinity() Float:

# Returns NaN, the Float that is not equal to itself under IEEE rules; use `is_nan()` to detect it.
export fn nan() Float:

# Returns the difference between 1.0 and the next larger Float.
export fn epsilon() Float:

# Returns the largest finite Float.
export fn max_float() Float:

# Returns the smallest positive Float, a subnormal value.
export fn min_float() Float:

# Returns the largest Int.
export fn max_int() Int:

# Returns the smallest Int.
export fn min_int() Int:

# Returns 2^53 - 1, the largest integer every smaller integer of which a Float represents exactly.
export fn max_safe_integer() Int:

# Returns -(2^53 - 1).
export fn min_safe_integer() Int:

# Returns the natural logarithm of 2.
export fn ln2() Float:

# Returns the natural logarithm of 10.
export fn ln10() Float:

# Returns the base-2 logarithm of e.
export fn log2e() Float:

# Returns the base-10 logarithm of e.
export fn log10e() Float:

# Returns the square root of 2.
export fn sqrt2() Float:

# Returns the square root of 1/2.
export fn sqrt_half() Float:
