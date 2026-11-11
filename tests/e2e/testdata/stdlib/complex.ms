import (
	Complex, complex, complex_polar, imaginary_unit from "@std/math/complex.ms",
	infinity, sign_bit from "@std/math/math.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

fn near(left: Complex, right: Complex) Bool:
	return left.subtract(right).abs() < 1e-12

fn component_close(actual: Float, expected: Float) Unit!:
	if expected.is_finite(): return expect_true((actual / expected - 1.0).abs() < 1e-12)
	return expect_equal(actual, expected)

test "complex arithmetic":
	a := complex(1.0, 2.0)
	b := complex(3.0, -1.0)
	expect_equal(a.add(b), complex(4.0, 1.0))?
	expect_equal(a.subtract(b), complex(-2.0, 3.0))?
	expect_equal(a.multiply(b), complex(5.0, 5.0))?
	expect_true(near(a.multiply(b).divide(b), a))?
	expect_equal(imaginary_unit().multiply(imaginary_unit()), complex(-1.0, 0.0))?
	expect_equal(a.conjugate(), complex(1.0, -2.0))?
	expect_equal(complex(3.0, 4.0).abs(), 5.0)?
	expect_equal(a.format(), "1+2i")?
	expect_equal(b.format(), "3-1i")?

test "complex polar form and elementary functions":
	z := complex_polar(2.0, 0.5)
	expect_true((z.abs() - 2.0).abs() < 1e-12)?
	expect_true((z.phase() - 0.5).abs() < 1e-12)?
	expect_true(near(complex(0.0, 3.141592653589793).exp(), complex(-1.0, 0.0)))?
	expect_true(near(complex(-4.0, 0.0).sqrt(), complex(0.0, 2.0)))?
	expect_true(near(complex(3.0, 4.0).sqrt(), complex(2.0, 1.0)))?
	expect_true(near(complex(2.0, 1.0).log().exp(), complex(2.0, 1.0)))?
	expect_true(near(imaginary_unit().pow(complex(2.0, 0.0)), complex(-1.0, 0.0)))?
	expect_true(near(complex(0.3, 0.4).sin().asin(), complex(0.3, 0.4)))?
	expect_true(near(complex(0.3, 0.4).cos().acos(), complex(0.3, 0.4)))?
	expect_true(near(complex(0.3, 0.4).tan().atan(), complex(0.3, 0.4)))?
	expect_true(
		near(
			complex(0.3, 0.4).sinh().divide(complex(0.3, 0.4).cosh()),
			complex(0.3, 0.4).tanh(),
		)
	)?

test "complex division by zero follows float rules":
	expect_true(
		complex(1.0, 1.0).divide(complex(0.0, 0.0)).is_nan() or complex(
			1.0,
			1.0,
		).divide(complex(0.0, 0.0)).is_infinite()
	)?
	expect_equal(complex(0.0, 0.0).pow(complex(0.0, 0.0)), complex(1.0, 0.0))?

test "complex exp keeps a zero imaginary part when the radius overflows":
	expect_equal(complex(710.0, 0.0).exp(), complex(infinity, 0.0))?

// References use the exact binary64 inputs evaluated with 100 decimal digits.
// Relative checks reject infinity and preserve components much smaller than 1e-12.
test "complex exp keeps finite components when the radius overflows":
	for phase in [0.75, -0.75]:
		result := complex(710.0, phase).exp()
		expected_im := if phase > 0.0: 1.522777422305087e308 else: -1.522777422305087e308
		expect_true((result.re / 1.6345891035228982e308 - 1.0).abs() < 1e-12)?
		expect_true((result.im / expected_im - 1.0).abs() < 1e-12)?

	negative_real := complex(710.0, 2.4).exp()
	expect_true((negative_real.re / -1.6473337011196798e308 - 1.0).abs() < 1e-12)?
	expect_true((negative_real.im / 1.5089812100862142e308 - 1.0).abs() < 1e-12)?

	near_axis := complex(710.0, 1.5707963267948966).exp()
	expect_true((near_axis.re / 1.3679272698459396e292 - 1.0).abs() < 1e-12)?
	expect_equal(near_axis.im, infinity)?

test "complex exp preserves tiny phase components after radius overflow":
	inputs := [
		complex(710.0, 5e-324),
		complex(1000.0, 1e-300),
		complex(1420.0, 5e-324),
		complex(1450.0, 5e-324),
	]
	expected := [
		1.1037400669496503e-15, 1.970071114017047e134, 2.4657495327684952e293,
		2.6350169706336343e306
	]

	for index in 0..inputs.length():
		value := inputs[index]
		positive := value.exp()
		negative := value.conjugate().exp()
		expect_equal(positive.re, infinity)?
		expect_equal(negative.re, infinity)?
		expect_true((positive.im / expected[index] - 1.0).abs() < 1e-12)?
		expect_true((negative.im / -expected[index] - 1.0).abs() < 1e-12)?

test "complex exp retains overflow and nonfinite controls":
	for real in [3000.0, 1.7976931348623157e308]:
		expect_equal(complex(real, 0.75).exp(), complex(infinity, infinity))?

		axis := complex(real, -0.0).exp()
		expect_equal(axis.re, infinity)?
		expect_equal(axis.im, 0.0)?
		expect_true(sign_bit(axis.im))?

	expect_true(complex(710.0, infinity).exp().is_nan())?
	expect_true(complex(infinity, 0.75).exp().is_infinite())?
	expect_true(complex(0.0 / 0.0, 0.75).exp().is_nan())?

// Exact binary64 inputs evaluated with 750 decimal digits. Check each
// component separately: one legitimately overflows while the other fits.
test "complex trig keeps finite components after hyperbolic overflow":
	phases := [0.5, 1.0, -0.5, -1.0]
	sine_parts := [1.4556863256554153e308, infinity, -1.4556863256554153e308, -infinity]
	cosine_parts := [infinity, 1.640527287432755e308, infinity, 1.640527287432755e308]

	for index in 0..phases.length():
		for argument in [711.0, -711.0]:
			direction := if argument > 0.0: 1.0 else: -1.0
			sine := complex(phases[index], argument).sin()
			component_close(sine.re, sine_parts[index])?
			component_close(sine.im, direction * cosine_parts[index])?

			cosine := complex(phases[index], argument).cos()
			component_close(cosine.re, cosine_parts[index])?
			component_close(cosine.im, -direction * sine_parts[index])?

			hyperbolic_sine := complex(argument, phases[index]).sinh()
			component_close(hyperbolic_sine.re, direction * cosine_parts[index])?
			component_close(hyperbolic_sine.im, sine_parts[index])?

			hyperbolic_cosine := complex(argument, phases[index]).cosh()
			component_close(hyperbolic_cosine.re, cosine_parts[index])?
			component_close(hyperbolic_cosine.im, direction * sine_parts[index])?

test "complex trig keeps subnormal phases beyond a half exponential":
	phases := [5e-324, 1e-300, 5e-324, 5e-324]
	arguments := [711.0, 1000.0, 1420.0, 1450.0]
	expected := [
		1.5001382836657022e-15, 9.850355570085236e133, 1.2328747663842476e293,
		1.3175084853168172e306
	]

	for index in 0..phases.length():
		for sign in [1.0, -1.0]:
			phase := sign * phases[index]

			for direction in [1.0, -1.0]:
				argument := direction * arguments[index]
				sine := complex(phase, argument).sin()
				component_close(sine.re, sign * expected[index])?
				expect_equal(sine.im, direction * infinity)?

				cosine := complex(phase, argument).cos()
				expect_equal(cosine.re, infinity)?
				component_close(cosine.im, -direction * sign * expected[index])?

				hyperbolic_sine := complex(argument, phase).sinh()
				expect_equal(hyperbolic_sine.re, direction * infinity)?
				component_close(hyperbolic_sine.im, sign * expected[index])?

				hyperbolic_cosine := complex(argument, phase).cosh()
				expect_equal(hyperbolic_cosine.re, infinity)?
				component_close(
					hyperbolic_cosine.im,
					direction * sign * expected[index],
				)?

test "complex trig range fallback retains signed zeros and nonfinite controls":
	expect_true(sign_bit(complex(-0.0, 1000.0).sin().re))?
	expect_true(not sign_bit(complex(0.0, -1000.0).sin().re))?
	expect_true(sign_bit(complex(0.0, 1000.0).cos().im))?
	expect_true(not sign_bit(complex(0.0, -1000.0).cos().im))?
	expect_true(sign_bit(complex(-1000.0, -0.0).sinh().im))?
	expect_true(not sign_bit(complex(-1000.0, -0.0).cosh().im))?
	expect_equal(complex(1.0, 3000.0).sin(), complex(infinity, infinity))?
	expect_equal(complex(3000.0, 1.0).sinh(), complex(infinity, infinity))?
	expect_equal(complex(0.0, infinity).sin(), complex(0.0, infinity))?
	expect_equal(complex(infinity, 0.0).cosh(), complex(infinity, 0.0))?
	expect_true(complex(infinity, 711.0).sin().is_nan())?
	expect_true(complex(711.0, 0.0 / 0.0).sinh().is_nan())?

test "complex sqrt stays finite when the magnitude overflows":
	root := complex(1.7e308, 1.7e308).sqrt()
	expect_true(root.re.is_finite() and root.im.is_finite())?

	square := root.scale(1e-100).multiply(root.scale(1e-100))
	expect_true(near(square.scale(1e-108), complex(1.7, 1.7)))?

test "complex trig keeps exact zeros and finite limits when parts overflow":
	expect_equal(complex(0.0, 1000.0).sin(), complex(0.0, infinity))?
	expect_equal(complex(0.0, 1000.0).cos(), complex(infinity, -0.0))?
	expect_equal(complex(0.0, 1000.0).tan(), complex(0.0, 1.0))?
	expect_equal(complex(0.0, -1000.0).tan(), complex(-0.0, -1.0))?
	expect_equal(complex(1000.0, 0.0).tanh(), complex(1.0, 0.0))?
	expect_equal(complex(-1000.0, 0.0).sinh(), complex(-infinity, 0.0))?

test "complex divide keeps a finite quotient when the operands are near the Float limits":
	big := complex(1.0e308, 1.0e308)
	expect_equal(big.divide(big), complex(1.0, 0.0))?

	tiny := complex(5.0e-324, 5.0e-324)
	expect_equal(tiny.divide(tiny), complex(1.0, 0.0))?
	expect_equal(
		complex(1.0e308, 0.0).divide(complex(0.0, 1.0e308)),
		complex(0.0, -1.0),
	)?
	expect_equal(complex(1.0e308, 0.0).divide(complex(1.0e308, 0.0)), complex(1.0, 0.0))?
	expect_equal(
		complex(0.0, 1.0e308).divide(complex(0.0, -1.0e308)),
		complex(-1.0, 0.0),
	)?

test "complex log is finite when the magnitude overflows":
	result := complex(1.7e308, 1.7e308).log()
	expect_true(result.re.is_finite())?
	expect_true(near(result, complex(710.0734104835082, 0.7853981633974483)))?

	axis := complex(-1.7e308, 0.0).log()
	expect_true(near(axis, complex(709.7268368932282, 3.141592653589793)))?
	expect_true(near(complex(1.0, 0.0).log(), complex(0.0, 0.0)))?

test "complex sqrt keeps a finite root for a subnormal input":
	root := complex(0.0, 5.0e-324).sqrt()
	expect_true(root.re > 0.0 and root.re.is_finite())?
	expect_true(root.im > 0.0 and root.im.is_finite())?
	expect_true(root.re / 1.5717277847026288e-162 > 0.999999999)?
	expect_true(root.re / 1.5717277847026288e-162 < 1.000000001)?

	below := complex(0.0, -5.0e-324).sqrt()
	expect_true(below.re > 0.0 and below.im < 0.0)?

// The small component needs relative checks: the ordinary near helper would
// accept zero here and conceal lost phase information.
test "complex tangent preserves huge finite phases":
	for phase in [1.0e308, -1.0e308]:
		expected := if phase > 0.0: -3.948379522881268e-36 else: 3.948379522881268e-36

		for magnitude in [41.0, -41.0]:
			tangent := complex(phase, magnitude).tan()
			expect_true(tangent.re.is_finite())?
			expect_true((tangent.re / expected - 1.0).abs() < 1e-12)?
			expect_equal(tangent.im, if magnitude > 0.0: 1.0 else: -1.0)?

			hyperbolic := complex(magnitude, phase).tanh()
			expect_true(hyperbolic.im.is_finite())?
			expect_true((hyperbolic.im / expected - 1.0).abs() < 1e-12)?
			expect_equal(hyperbolic.re, if magnitude > 0.0: 1.0 else: -1.0)?

test "complex tangent handles the largest finite phase":
	phase := 1.7976931348623157e308
	expected := -4.847970089451913e-38
	tangent := complex(phase, 41.0).tan()
	expect_true((tangent.re / expected - 1.0).abs() < 1e-12)?
	expect_equal(tangent.im, 1.0)?

	hyperbolic := complex(41.0, phase).tanh()
	expect_true((hyperbolic.im / expected - 1.0).abs() < 1e-12)?
	expect_equal(hyperbolic.re, 1.0)?

// Exact binary64 inputs evaluated with 750 decimal digits. An absolute
// complex-distance check would accept zero for every small component here.
test "complex inverse tangent preserves small imaginary components":
	inputs := [
		complex(1.0, 1e-30),
		complex(0.0, 1e-30),
		complex(2.0, 1e-300),
		complex(1e200, 1e200),
		complex(1e308, 1e308),
		complex(1e200, 1e100),
		complex(0.0, 1e200),
	]
	expected := [5e-31, 1e-30, 2e-301, 5e-201, 5e-309, 1e-300, 1e-200]

	for index in 0..inputs.length():
		value := inputs[index]
		positive := value.atan()
		negative := value.conjugate().atan()
		expect_true((positive.im / expected[index] - 1.0).abs() < 1e-12)?
		expect_true((negative.im / -expected[index] - 1.0).abs() < 1e-12)?
		if value.re != 0.0:
			expect_equal(positive.re, negative.re)?

test "complex inverse tangent retains subnormal components":
	for real in [0.0, 0.8, -0.8]:
		expect_equal(complex(real, 5e-324).atan().im, 5e-324)?
		expect_equal(complex(real, -5e-324).atan().im, -5e-324)?

	largest := complex(1.7976931348623157e308, 1.7976931348623157e308).atan()
	expect_equal(largest.im, 2.781342323134e-309)?

test "complex inverse tangent preserves poles and ordinary controls":
	upper_pole := complex(0.0, 1.0).atan()
	lower_pole := complex(0.0, -1.0).atan()
	expect_equal(upper_pole.im, infinity)?
	expect_equal(lower_pole.im, -infinity)?

	near_pole := complex(1e-300, 1.0).atan()
	expect_true((near_pole.re / 0.7853981633974483 - 1.0).abs() < 1e-12)?
	expect_true((near_pole.im / 345.7343375393868 - 1.0).abs() < 1e-12)?
	expect_true(
		near(
			complex(1.0, 0.5).atan(),
			complex(0.847575660670829, 0.2388778612568591),
		)
	)?
	expect_true(near(complex(0.3, 0.4).tan().atan(), complex(0.3, 0.4)))?
	expect_true(complex(infinity, 1.0).atan().is_nan())?
	expect_true(complex(1.0, 0.0 / 0.0).atan().is_nan())?

	negative_zero := complex(1.0, -0.0).atan()
	expect_equal(negative_zero.im, 0.0)?
	expect_true(sign_bit(negative_zero.im))?

test "inverse sine keeps large imaginary parts finite and conjugate-symmetric":
	// asin(i*y) = i*asinh(y); asinh(1e10) = 23.7189981105004...
	for y in [1e10, 1e100]:
		up := complex(0.0, y).asin()
		down := complex(0.0, -y).asin()
		expect_true(up.re == 0.0 and down.re == 0.0)?
		expect_true(up.im.is_finite() and up.im > 0.0)?
		expect_equal(up.im, -down.im)?

	component_close(complex(0.0, 1e10).asin().im, 23.7189981105004)?
	expect_true(
		near(
			complex(0.0, 1e10).acos(),
			complex(1.5707963267948966, -23.7189981105004),
		)
	)?
	component_close(complex(0.5, 1e6).asin().im, 14.508657738524594)?
	component_close(complex(-1e5, 2.0).asin().re, -1.5707763267948982)?

	// Ordinary points are unchanged and symmetric under conjugation and negation.
	z := complex(3.0, 4.0)
	expect_true(near(z.asin(), complex(0.6339838656391766, 2.305509031243477)))?
	expect_true(near(z.conjugate().asin(), z.asin().conjugate()))?
	expect_true(
		near(
			z.multiply(complex(-1.0, 0.0)).asin(),
			z.asin().multiply(complex(-1.0, 0.0)),
		)
	)?

test "complex divide keeps a small part beside a part near the Float limit":
	z := complex(1.0e308, 1.0e-100)
	expect_equal(z.divide(complex(1.0, 0.0)), z)?

	swapped := complex(1.0e-100, 1.0e308)
	expect_equal(swapped.divide(complex(1.0, 0.0)), swapped)?
	expect_equal(
		complex(-1.0e308, 1.0e-100).divide(complex(1.0, 0.0)),
		complex(-1.0e308, 1.0e-100),
	)?
	expect_equal(z.divide(complex(2.0, 0.0)), complex(5.0e307, 5.0e-101))?
