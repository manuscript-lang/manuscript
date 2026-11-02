import (
    atan2,
    copy_sign,
    cos,
    cosh,
    exp,
    hypot,
    infinity,
    log,
    sign_bit,
    sin,
    sinh,
    sqrt
) from "@std/math/math.ms"

# A complex number with `Float` parts. It is plain data and copies freely.
# Arithmetic uses named methods; `Complex(re: 1.0, im: 2.0).multiply(complex(0.0, 1.0))` is `-2 + 1i`.
export type Complex:
    # The real part, a Float that may be infinite or NaN.
    re: Float
    # The imaginary part, a Float that may be infinite or NaN.
    im: Float

# Returns the complex number `re + im*i`.
export fn complex(re: Float, im: Float) Complex:
    return Complex(re: re, im: im)

# Returns the number with magnitude `radius` and angle `theta` in radians, so `complex_polar(1.0, pi)` is about -1.
export fn complex_polar(radius: Float, theta: Float) Complex:
    return Complex(re: radius * cos(theta), im: radius * sin(theta))

# Returns the imaginary unit `i`.
export fn imaginary_unit() Complex:
    return Complex(re: 0.0, im: 1.0)

# A polar decomposition from `to_polar`.
export type PolarParts:
    # The magnitude, never negative.
    radius: Float
    # The angle in radians, from -pi through pi.
    theta: Float

impl Complex:
    # Returns the sum, adding real and imaginary parts separately with Float rounding.
    fn add(other: Complex) Complex:
        return Complex(re: self.re + other.re, im: self.im + other.im)

    # Returns the difference, subtracting real and imaginary parts separately with Float rounding.
    fn subtract(other: Complex) Complex:
        return Complex(re: self.re - other.re, im: self.im - other.im)

    # Returns the product `(a+bi)(c+di) = (ac-bd) + (ad+bc)i` with Float rounding.
    fn multiply(other: Complex) Complex:
        return Complex(
            re: self.re * other.re - self.im * other.im,
            im: self.re * other.im + self.im * other.re
        )

    # Returns the product with a real factor.
    fn scale(factor: Float) Complex:
        return Complex(re: self.re * factor, im: self.im * factor)

    # Returns the quotient. Dividing by zero follows Float rules and gives infinities or NaN, never a fault.
    # The divisor is scaled by its larger part to avoid overflow in the intermediate squares.
    fn divide(other: Complex) Complex:
        let abs_re = other.re.abs()
        let abs_im = other.im.abs()

        if abs_re >= abs_im:
            let ratio = other.im / other.re
            let denominator = other.re + other.im * ratio
            return Complex(
                re: (self.re + self.im * ratio) / denominator,
                im: (self.im - self.re * ratio) / denominator
            )

        let ratio = other.re / other.im
        let denominator = other.re * ratio + other.im
        return Complex(
            re: (self.re * ratio + self.im) / denominator,
            im: (self.im * ratio - self.re) / denominator
        )

    # Returns the number with both parts negated.
    fn negate() Complex:
        return Complex(re: -self.re, im: -self.im)

    # Returns the number with the imaginary part negated, so `(1+2i)` becomes `(1-2i)`.
    fn conjugate() Complex:
        return Complex(re: self.re, im: -self.im)

    # Returns the magnitude `sqrt(re^2 + im^2)` without intermediate overflow.
    fn abs() Float:
        return hypot(self.re, self.im)

    # Returns the angle in radians, from -pi through pi; the principal argument.
    fn phase() Float:
        return atan2(self.im, self.re)

    # Returns magnitude and angle together.
    fn to_polar() PolarParts:
        return PolarParts(radius: self.abs(), theta: self.phase())

    # True when either part is NaN.
    fn is_nan() Bool:
        return self.re.is_nan() or self.im.is_nan()

    # True when either part is infinite and neither is NaN.
    fn is_infinite() Bool:
        if self.is_nan():
            return false

        return (
            not self.re.is_finite() and not self.re.is_nan()
            or not self.im.is_finite() and not self.im.is_nan()
        )

    # Returns `e` raised to this number.
    fn exp() Complex:
        return complex_polar(exp(self.re), self.im)

    # Returns the principal natural logarithm; the imaginary part is the phase.
    fn log() Complex:
        return Complex(re: log(self.abs()), im: self.phase())

    # Returns the principal square root, with a non-negative real part.
    fn sqrt() Complex:
        if self.im == 0.0:
            if self.re >= 0.0:
                return Complex(re: sqrt(self.re), im: self.im)

            return Complex(re: 0.0, im: copy_sign(sqrt(-self.re), self.im))

        let modulus = self.abs()
        let real = sqrt((modulus + self.re.abs()) / 2.0)
        if self.re >= 0.0:
            return Complex(re: real, im: self.im / (2.0 * real))

        return Complex(re: self.im.abs() / (2.0 * real), im: copy_sign(real, self.im))

    # Returns this number raised to `exponent`: 0^0 is 1, and a zero base with a positive exponent real part is 0.
    fn pow(exponent: Complex) Complex:
        if self.re == 0.0 and self.im == 0.0:
            if exponent.re == 0.0 and exponent.im == 0.0:
                return Complex(re: 1.0, im: 0.0)
            if exponent.re > 0.0:
                return Complex(re: 0.0, im: 0.0)

            return Complex(re: infinity, im: 0.0)

        return self.log().multiply(exponent).exp()

    # Returns the complex sine, `sin(a)cosh(b) + cos(a)sinh(b)i` for `a+bi`.
    fn sin() Complex:
        return Complex(
            re: sin(self.re) * cosh(self.im), im: cos(self.re) * sinh(self.im)
        )

    # Returns the complex cosine, `cos(a)cosh(b) - sin(a)sinh(b)i` for `a+bi`.
    fn cos() Complex:
        return Complex(
            re: cos(self.re) * cosh(self.im), im: -(sin(self.re) * sinh(self.im))
        )

    # Returns the complex tangent, sine divided by cosine; poles give infinities or NaN.
    fn tan() Complex:
        return self.sin().divide(self.cos())

    # Returns the hyperbolic sine.
    fn sinh() Complex:
        return Complex(
            re: sinh(self.re) * cos(self.im), im: cosh(self.re) * sin(self.im)
        )

    # Returns the hyperbolic cosine.
    fn cosh() Complex:
        return Complex(
            re: cosh(self.re) * cos(self.im), im: sinh(self.re) * sin(self.im)
        )

    # Returns the hyperbolic tangent.
    fn tanh() Complex:
        return self.sinh().divide(self.cosh())

    # Returns the principal inverse sine, `-i * log(i*z + sqrt(1 - z^2))`.
    fn asin() Complex:
        let root = Complex(re: 1.0, im: 0.0).subtract(self.multiply(self)).sqrt()
        let inner = imaginary_unit().multiply(self).add(root).log()
        return Complex(re: inner.im, im: -inner.re)

    # Returns the principal inverse cosine, pi/2 minus the inverse sine.
    fn acos() Complex:
        let s = self.asin()
        return Complex(re: 1.5707963267948966 - s.re, im: -s.im)

    # Returns the principal inverse tangent, `i/2 * (log(1 - iz) - log(1 + iz))`.
    fn atan() Complex:
        let iz = imaginary_unit().multiply(self)
        let diff = Complex(re: 1.0, im: 0.0).subtract(iz).log().subtract(
            Complex(re: 1.0, im: 0.0).add(iz).log()
        )
        return Complex(re: -diff.im / 2.0, im: diff.re / 2.0)

    # Formats as `a+bi` or `a-bi` using the Float text of each part, e.g. `1.5-2i`.
    fn format() String:
        if sign_bit(self.im):
            return "{self.re}-{(-self.im)}i"

        return "{self.re}+{self.im}i"
