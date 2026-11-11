import (
	atan2,
	copy_sign,
	cos,
	cosh,
	exp,
	frexp,
	hypot,
	infinity,
	ldexp,
	log,
	log1p,
	sign_bit,
	sin,
	sinh,
	sqrt
) from "@std/math/math.ms"

// A complex number with `Float` parts. It is plain data and copies freely.
// Arithmetic uses named methods; `Complex(re: 1.0, im: 2.0).multiply(complex(0.0, 1.0))` is `-2 + 1i`.
export type Complex:
	// The real part, a Float that may be infinite or NaN.
	re: Float
	// The imaginary part, a Float that may be infinite or NaN.
	im: Float

impl Complex:
	// Returns the sum, adding real and imaginary parts separately with Float rounding.
	fn add(other: Complex) Complex:
		return Complex(re: self.re + other.re, im: self.im + other.im)

	// Returns the difference, subtracting real and imaginary parts separately with Float rounding.
	fn subtract(other: Complex) Complex:
		return Complex(re: self.re - other.re, im: self.im - other.im)

	// Returns the product `(a+bi)(c+di) = (ac-bd) + (ad+bc)i` with Float rounding.
	fn multiply(other: Complex) Complex:
		return Complex(
			re: self.re * other.re - self.im * other.im,
			im: self.re * other.im + self.im * other.re
		)

	// Returns the product with a real factor.
	fn scale(factor: Float) Complex:
		return Complex(re: self.re * factor, im: self.im * factor)

	// Returns the quotient. Dividing by zero follows Float rules and gives infinities or NaN, never a fault.
	// The divisor is scaled by its larger part to avoid overflow in the intermediate squares.
	// Finite operands whose parts are near the Float range limits are first scaled by exact powers of two so the quotient keeps its precision; a numerator is only scaled enough to stay in range, so its smaller part survives.
	fn divide(other: Complex) Complex:
		sn := self.re.abs().max(self.im.abs())
		sd := other.re.abs().max(other.im.abs())

		if (
			sd > 0.0
			and sn.is_finite()
			and sd.is_finite()
			and (
				sn.max(sd) > 3.273390607896142e150
				or sd < 3.054936363499605e-151
				or sn > 0.0 and sn < 3.054936363499605e-151
			)
		):
			// Only pull the numerator back into range when it is extreme, and keep its larger part near 2^900:
			// scaling it down to 1 would underflow a much smaller part that the quotient still needs.
			exponent := frexp(sn).exponent
			var numerator_exponent = 0
			if exponent > 900: numerator_exponent = exponent - 900
			if exponent < -900: numerator_exponent = exponent + 900

			divisor_exponent := frexp(sd).exponent
			quotient := smith_divide(
				Complex(
					re: ldexp(self.re, -numerator_exponent),
					im: ldexp(self.im, -numerator_exponent)
				),
				Complex(
					re: ldexp(other.re, -divisor_exponent),
					im: ldexp(other.im, -divisor_exponent)
				)
			)
			shift := numerator_exponent - divisor_exponent
			return Complex(re: ldexp(quotient.re, shift), im: ldexp(quotient.im, shift))

		return smith_divide(self, other)

	// Returns the number with both parts negated.
	fn negate() Complex:
		return Complex(re: -self.re, im: -self.im)

	// Returns the number with the imaginary part negated, so `(1+2i)` becomes `(1-2i)`.
	fn conjugate() Complex:
		return Complex(re: self.re, im: -self.im)

	// Returns the magnitude `sqrt(re^2 + im^2)` without intermediate overflow.
	fn abs() Float:
		return hypot(self.re, self.im)

	// Returns the angle in radians, from -pi through pi; the principal argument.
	fn phase() Float:
		return atan2(self.im, self.re)

	// Returns magnitude and angle together.
	fn to_polar() PolarParts:
		return PolarParts(radius: self.abs(), theta: self.phase())

	// True when either part is NaN.
	fn is_nan() Bool:
		return self.re.is_nan() or self.im.is_nan()

	// True when either part is infinite and neither is NaN.
	fn is_infinite() Bool:
		if self.is_nan(): return false
		return (
			not self.re.is_finite() and not self.re.is_nan()
			or not self.im.is_finite() and not self.im.is_nan()
		)

	// Returns `e` raised to this number.
	fn exp() Complex:
		radius := exp(self.re)

		// A zero imaginary part stays zero where the radius overflows; `inf * sin(0)` would be NaN.
		if self.im == 0.0: return Complex(re: radius, im: self.im)

		// The full radius can overflow while either final component still fits.
		// Four growing factors also preserve tiny phases beyond the half-exponential range.
		if not radius.is_finite() and self.re.is_finite() and self.im.is_finite():
			quarter := exp(self.re / 4.0)
			var result = Complex(re: cos(self.im), im: sin(self.im))
			for _step in 0..4:
				result = Complex(
					re: product(result.re, quarter), im: product(result.im, quarter)
				)
			return result

		return complex_polar(radius, self.im)

	// Returns the principal natural logarithm; the imaginary part is the phase.
	fn log() Complex:
		modulus := self.abs()

		// A finite number whose magnitude overflows still has a finite logarithm: log(m) = log(m/2) + ln 2.
		if not modulus.is_finite() and self.re.is_finite() and self.im.is_finite():
			return Complex(
				re: log(
					hypot(self.re / 2.0, self.im / 2.0)
				) + 0.6931471805599453,
				im: self.phase()
			)

		return Complex(re: log(modulus), im: self.phase())

	// Returns the principal square root, with a non-negative real part.
	fn sqrt() Complex:
		if self.im == 0.0:
			if self.re >= 0.0: return Complex(re: sqrt(self.re), im: self.im)
			return Complex(re: 0.0, im: copy_sign(sqrt(-self.re), self.im))

		modulus := self.abs()

		// A finite number whose magnitude overflows has a finite root: take the root of the half and scale by sqrt(2).
		if not modulus.is_finite() and self.re.is_finite() and self.im.is_finite():
			return Complex(re: self.re / 2.0, im: self.im / 2.0).sqrt().scale(sqrt(2.0))

		// Halving a subnormal modulus loses its low bits: scale up by 2^200, take the root, and scale back by 2^-100.
		if modulus < 4.450147717014403e-308:
			root := Complex(re: ldexp(self.re, 200), im: ldexp(self.im, 200)).sqrt()
			return Complex(re: ldexp(root.re, -100), im: ldexp(root.im, -100))

		real := sqrt(modulus / 2.0 + self.re.abs() / 2.0)
		if self.re >= 0.0: return Complex(re: real, im: self.im / (2.0 * real))

		return Complex(re: self.im.abs() / (2.0 * real), im: copy_sign(real, self.im))

	// Returns this number raised to `exponent`: 0^0 is 1, and a zero base with a positive exponent real part is 0.
	fn pow(exponent: Complex) Complex:
		if self.re == 0.0 and self.im == 0.0:
			if exponent.re == 0.0 and exponent.im == 0.0:
				return Complex(re: 1.0, im: 0.0)
			if exponent.re > 0.0: return Complex(re: 0.0, im: 0.0)

			return Complex(re: infinity, im: 0.0)

		return self.log().multiply(exponent).exp()

	// Returns the complex sine, `sin(a)cosh(b) + cos(a)sinh(b)i` for `a+bi`.
	fn sin() Complex:
		return Complex(
			re: hyperbolic_product(sin(self.re), self.im, cosh(self.im)),
			im: hyperbolic_product(cos(self.re), self.im, sinh(self.im))
		)

	// Returns the complex cosine, `cos(a)cosh(b) - sin(a)sinh(b)i` for `a+bi`.
	fn cos() Complex:
		return Complex(
			re: hyperbolic_product(cos(self.re), self.im, cosh(self.im)),
			im: -hyperbolic_product(sin(self.re), self.im, sinh(self.im))
		)

	// Returns the complex tangent, sine divided by cosine; poles give infinities or NaN.
	fn tan() Complex:
		// Past |b| = 40 sine and cosine overflow into inf / inf; the quotient is `sign(b) * i` plus a real part below 1e-34.
		if self.im.abs() > 40.0:
			return Complex(
				re: 2.0 * sin_double(self.re) * exp(
					-2.0 * self.im.abs()
				),
				im: copy_sign(1.0, self.im)
			)
		return self.sin().divide(self.cos())

	// Returns the hyperbolic sine.
	fn sinh() Complex:
		return Complex(
			re: hyperbolic_product(cos(self.im), self.re, sinh(self.re)),
			im: hyperbolic_product(sin(self.im), self.re, cosh(self.re))
		)

	// Returns the hyperbolic cosine.
	fn cosh() Complex:
		return Complex(
			re: hyperbolic_product(cos(self.im), self.re, cosh(self.re)),
			im: hyperbolic_product(sin(self.im), self.re, sinh(self.re))
		)

	// Returns the hyperbolic tangent.
	fn tanh() Complex:
		// Past |a| = 40 the quotient is `sign(a)` plus an imaginary part below 1e-34.
		if self.re.abs() > 40.0:
			return Complex(
				re: copy_sign(1.0, self.re),
				im: 2.0 * sin_double(self.im) * exp(
					-2.0 * self.re.abs()
				)
			)
		return self.sinh().divide(self.cosh())

	// Returns the principal inverse sine, `-i * log(i*z + sqrt(1 - z^2))`.
	fn asin() Complex:
		// asin(-z) = -asin(z). In the upper half plane iz and the root have opposite real parts and cancel for large |im|, so evaluate through the lower half plane, where they add.
		sign := if self.im > 0.0: -1.0 else: 1.0
		z := Complex(re: sign * self.re, im: sign * self.im)
		root := Complex(re: 1.0, im: 0.0).subtract(z.multiply(z)).sqrt()
		inner := imaginary_unit().multiply(z).add(root).log()
		return Complex(re: sign * inner.im, im: -sign * inner.re)

	// Returns the principal inverse cosine, pi/2 minus the inverse sine.
	fn acos() Complex:
		s := self.asin()
		return Complex(re: 1.5707963267948966 - s.re, im: -s.im)

	// Returns the principal inverse tangent, `i/2 * (log(1 - iz) - log(1 + iz))`.
	fn atan() Complex:
		iz := imaginary_unit().multiply(self)
		diff := Complex(re: 1.0, im: 0.0).subtract(iz).log().subtract(
			Complex(re: 1.0, im: 0.0).add(iz).log()
		)
		var imaginary = diff.re / 2.0
		magnitude := self.re.abs().max(self.im.abs())

		// The logarithms cancel for a small imaginary part or large components.
		// log1p of their squared-magnitude ratio keeps the small difference.
		// Scaling avoids squares overflowing; near either pole keep the logs,
		// whose separate magnitudes do not underflow like a squared distance.
		if (
			self.re.is_finite()
			and self.im.is_finite()
			and (self.im.abs() < 0.5 or magnitude > 2.0)
		):
			scale := magnitude.max(1.0)
			real := self.re / scale
			offset := (self.im.abs() - 1.0) / scale
			denominator := real * real + offset * offset
			ratio := 4.0 * (self.im.abs() / scale) / denominator / scale

			if ratio < 1e-300:
				// log1p(t) is t here. Divide before the factor of four could
				// round a subnormal result twice.
				imaginary = copy_sign(
					self.im.abs() / denominator / scale / scale, self.im
				)
			else:
				imaginary = copy_sign(log1p(ratio) / 4.0, self.im)

		return Complex(re: -diff.im / 2.0, im: imaginary)

	// Formats as `a+bi` or `a-bi` using the Float text of each part, e.g. `1.5-2i`.
	fn format() String:
		if sign_bit(self.im): return "{self.re}-{(-self.im)}i"
		return "{self.re}+{self.im}i"

// Returns the complex number `re + im*i`.
export fn complex(re: Float, im: Float) Complex:
	return Complex(re: re, im: im)

// Returns the number with magnitude `radius` and angle `theta` in radians, so `complex_polar(1.0, pi)` is about -1.
export fn complex_polar(radius: Float, theta: Float) Complex:
	return Complex(re: radius * cos(theta), im: radius * sin(theta))

// Returns the imaginary unit `i`.
export fn imaginary_unit() Complex:
	return Complex(re: 0.0, im: 1.0)

// A polar decomposition from `to_polar`.
export type PolarParts:
	// The magnitude, never negative.
	radius: Float
	// The angle in radians, from -pi through pi.
	theta: Float

// Multiplies two factors where one may be an overflowed (infinite) trig or hyperbolic value. An exact zero times such an infinity stays a signed zero, where plain `*` would give NaN.
fn product(left: Float, right: Float) Float:
	if left == 0.0 and not right.is_finite() and not right.is_nan():
		return left * copy_sign(1.0, right)
	if right == 0.0 and not left.is_finite() and not left.is_nan():
		return right * copy_sign(1.0, left)

	return left * right

// A finite sinh/cosh argument can overflow before a small trig factor is
// applied. Grow that factor through exp(|argument|)/2 without materializing
// the full exponential; its reciprocal term is negligible in this range.
fn hyperbolic_product(factor: Float, argument: Float, value: Float) Float:
	if value.is_finite() or value.is_nan() or not argument.is_finite():
		return product(factor, value)

	quarter := exp(argument.abs() / 4.0)
	var result = factor
	for _step in 0..3:
		result = product(result, quarter)
	return product(result, quarter / 2.0) * copy_sign(1.0, value)

// Computes sin(2*x) without overflowing a finite phase when doubling it.
fn sin_double(phase: Float) Float:
	if phase.abs() > 8.988465674311579e307: return 2.0 * sin(phase) * cos(phase)
	return sin(2.0 * phase)

// Divides by the larger part of the divisor (Smith's algorithm).
fn smith_divide(numerator: Complex, other: Complex) Complex:
	abs_re := other.re.abs()
	abs_im := other.im.abs()

	if abs_re >= abs_im:
		ratio := other.im / other.re
		denominator := other.re + other.im * ratio
		return Complex(
			re: (numerator.re + numerator.im * ratio) / denominator,
			im: (numerator.im - numerator.re * ratio) / denominator
		)

	ratio := other.re / other.im
	denominator := other.re * ratio + other.im
	return Complex(
		re: (numerator.re * ratio + numerator.im) / denominator,
		im: (numerator.im * ratio - numerator.re) / denominator
	)
