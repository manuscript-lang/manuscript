# Canonical standard-library declarations. Implementations are native.

import NumberError from "@std/numbers.ms"

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

# Rounds to the nearest whole number, with half values toward positive infinity.
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

# Returns the greater signed 64-bit integer without converting to Float.
export fn max_int(left: Int, right: Int) -> Int:

# Returns the lesser signed 64-bit integer without converting to Float.
export fn min_int(left: Int, right: Int) -> Int:

# Raises an integer to a nonnegative integer exponent; zero to the zero power is one.
# Negative exponents return InvalidInput; signed 64-bit overflow returns OutOfRange.
export fn pow_int(base: Int, exponent: Int) -> Result[Int, NumberError]:

# Returns -1, 0, or 1 for the sign; preserves signed zero and propagates NaN.
export fn sign(value: Float) -> Float:

# Returns -1, 0, or 1 for the sign of a signed 64-bit integer.
export fn sign_int(value: Int) -> Int:

# Clamps a value to the inclusive bounds; NaN in any argument produces NaN.
# Reversed bounds fault; supply minimum <= maximum.
export fn clamp(value: Float, minimum: Float, maximum: Float) -> Float:

# Clamps an integer to the inclusive bounds without converting to Float.
# Reversed bounds fault; supply minimum <= maximum.
export fn clamp_int(value: Int, minimum: Int, maximum: Int) -> Int:

# Returns the real cube root, including for negative values.
export fn cbrt(value: Float) -> Float:

# Returns the inverse hyperbolic sine; infinities and NaN propagate.
export fn asinh(value: Float) -> Float:

# Returns the inverse hyperbolic cosine; values below one produce NaN.
export fn acosh(value: Float) -> Float:

# Returns the inverse hyperbolic tangent; values outside [-1, 1] produce NaN.
# At -1 and 1 the result is negative and positive infinity respectively.
export fn atanh(value: Float) -> Float:

# Rounds to the nearest integer with ties toward positive infinity, as round does.
# Returns none for nonfinite values or a rounded value outside signed 64-bit range.
export fn round_to_int(value: Float) -> Optional[Int]:

# Rounds downward and converts to Int; nonfinite or out-of-range results return none.
export fn floor_to_int(value: Float) -> Optional[Int]:

# Rounds upward and converts to Int; nonfinite or out-of-range results return none.
export fn ceil_to_int(value: Float) -> Optional[Int]:

# Adds integer values in order; an empty list sums to zero.
# Returns OutOfRange if any running total leaves the signed 64-bit range; input is unchanged.
export fn sum_int(values: List[Int]) -> Result[Int, NumberError]:

# Adds floating-point values in order using IEEE arithmetic; an empty list sums to zero.
# NaN and infinity follow ordinary Float addition; input is unchanged.
export fn sum_float(values: List[Float]) -> Float:
