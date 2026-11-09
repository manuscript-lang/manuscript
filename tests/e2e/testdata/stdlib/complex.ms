import expect_equal, expect_true from "@std/test/test.ms"
import infinity, sign_bit from "@std/math/math.ms"
import Complex, complex, complex_polar, imaginary_unit from "@std/math/complex.ms"

fn near(left: Complex, right: Complex) Bool:
    return left.subtract(right).abs() < 1e-12

test "complex arithmetic":
    let a = complex(1.0, 2.0)
    let b = complex(3.0, -1.0)
    try expect_equal(a.add(b), complex(4.0, 1.0))
    try expect_equal(a.subtract(b), complex(-2.0, 3.0))
    try expect_equal(a.multiply(b), complex(5.0, 5.0))
    try expect_true(near(a.multiply(b).divide(b), a))
    try expect_equal(imaginary_unit().multiply(imaginary_unit()), complex(-1.0, 0.0))
    try expect_equal(a.conjugate(), complex(1.0, -2.0))
    try expect_equal(complex(3.0, 4.0).abs(), 5.0)
    try expect_equal(a.format(), "1+2i")
    try expect_equal(b.format(), "3-1i")

test "complex polar form and elementary functions":
    let z = complex_polar(2.0, 0.5)
    try expect_true((z.abs() - 2.0).abs() < 1e-12)
    try expect_true((z.phase() - 0.5).abs() < 1e-12)
    try expect_true(near(complex(0.0, 3.141592653589793).exp(), complex(-1.0, 0.0)))
    try expect_true(near(complex(-4.0, 0.0).sqrt(), complex(0.0, 2.0)))
    try expect_true(near(complex(3.0, 4.0).sqrt(), complex(2.0, 1.0)))
    try expect_true(near(complex(2.0, 1.0).log().exp(), complex(2.0, 1.0)))
    try expect_true(near(imaginary_unit().pow(complex(2.0, 0.0)), complex(-1.0, 0.0)))
    try expect_true(near(complex(0.3, 0.4).sin().asin(), complex(0.3, 0.4)))
    try expect_true(near(complex(0.3, 0.4).cos().acos(), complex(0.3, 0.4)))
    try expect_true(near(complex(0.3, 0.4).tan().atan(), complex(0.3, 0.4)))
    try expect_true(
        near(
            complex(0.3, 0.4).sinh().divide(complex(0.3, 0.4).cosh()),
            complex(0.3, 0.4).tanh()
        )
    )

test "complex division by zero follows float rules":
    try expect_true(
        complex(1.0, 1.0).divide(complex(0.0, 0.0)).is_nan() or complex(
            1.0, 1.0
        ).divide(complex(0.0, 0.0)).is_infinite()
    )
    try expect_equal(complex(0.0, 0.0).pow(complex(0.0, 0.0)), complex(1.0, 0.0))

test "complex exp keeps a zero imaginary part when the radius overflows":
    try expect_equal(complex(710.0, 0.0).exp(), complex(infinity, 0.0))

// References use the exact binary64 inputs evaluated with 100 decimal digits.
// Relative checks reject infinity and preserve components much smaller than 1e-12.
test "complex exp keeps finite components when the radius overflows":
    for phase in [0.75, -0.75]:
        let result = complex(710.0, phase).exp()
        let expected_im = if phase > 0.0: 1.522777422305087e308 else: -1.522777422305087e308
        try expect_true((result.re / 1.6345891035228982e308 - 1.0).abs() < 1e-12)
        try expect_true((result.im / expected_im - 1.0).abs() < 1e-12)

    let negative_real = complex(710.0, 2.4).exp()
    try expect_true((negative_real.re / -1.6473337011196798e308 - 1.0).abs() < 1e-12)
    try expect_true((negative_real.im / 1.5089812100862142e308 - 1.0).abs() < 1e-12)

    let near_axis = complex(710.0, 1.5707963267948966).exp()
    try expect_true((near_axis.re / 1.3679272698459396e292 - 1.0).abs() < 1e-12)
    try expect_equal(near_axis.im, infinity)

test "complex exp preserves tiny phase components after radius overflow":
    let inputs = [
        complex(710.0, 5e-324), complex(1000.0, 1e-300), complex(1420.0, 5e-324),
        complex(1450.0, 5e-324)
    ]
    let expected = [
        1.1037400669496503e-15, 1.970071114017047e134, 2.4657495327684952e293,
        2.6350169706336343e306
    ]

    for index in 0..inputs.length():
        let value = inputs[index]
        let positive = value.exp()
        let negative = value.conjugate().exp()
        try expect_equal(positive.re, infinity)
        try expect_equal(negative.re, infinity)
        try expect_true((positive.im / expected[index] - 1.0).abs() < 1e-12)
        try expect_true((negative.im / -expected[index] - 1.0).abs() < 1e-12)

test "complex exp retains overflow and nonfinite controls":
    for real in [3000.0, 1.7976931348623157e308]:
        try expect_equal(complex(real, 0.75).exp(), complex(infinity, infinity))

        let axis = complex(real, -0.0).exp()
        try expect_equal(axis.re, infinity)
        try expect_equal(axis.im, 0.0)
        try expect_true(sign_bit(axis.im))

    try expect_true(complex(710.0, infinity).exp().is_nan())
    try expect_true(complex(infinity, 0.75).exp().is_infinite())
    try expect_true(complex(0.0 / 0.0, 0.75).exp().is_nan())

test "complex sqrt stays finite when the magnitude overflows":
    let root = complex(1.7e308, 1.7e308).sqrt()
    try expect_true(root.re.is_finite() and root.im.is_finite())

    let square = root.scale(1e-100).multiply(root.scale(1e-100))
    try expect_true(near(square.scale(1e-108), complex(1.7, 1.7)))

test "complex trig keeps exact zeros and finite limits when parts overflow":
    try expect_equal(complex(0.0, 1000.0).sin(), complex(0.0, infinity))
    try expect_equal(complex(0.0, 1000.0).cos(), complex(infinity, -0.0))
    try expect_equal(complex(0.0, 1000.0).tan(), complex(0.0, 1.0))
    try expect_equal(complex(0.0, -1000.0).tan(), complex(-0.0, -1.0))
    try expect_equal(complex(1000.0, 0.0).tanh(), complex(1.0, 0.0))
    try expect_equal(complex(-1000.0, 0.0).sinh(), complex(-infinity, 0.0))

test "complex divide keeps a finite quotient when the operands are near the Float limits":
    let big = complex(1.0e308, 1.0e308)
    try expect_equal(big.divide(big), complex(1.0, 0.0))

    let tiny = complex(5.0e-324, 5.0e-324)
    try expect_equal(tiny.divide(tiny), complex(1.0, 0.0))
    try expect_equal(
        complex(1.0e308, 0.0).divide(complex(0.0, 1.0e308)), complex(0.0, -1.0)
    )
    try expect_equal(
        complex(1.0e308, 0.0).divide(complex(1.0e308, 0.0)), complex(1.0, 0.0)
    )
    try expect_equal(
        complex(0.0, 1.0e308).divide(complex(0.0, -1.0e308)), complex(-1.0, 0.0)
    )

test "complex log is finite when the magnitude overflows":
    let result = complex(1.7e308, 1.7e308).log()
    try expect_true(result.re.is_finite())
    try expect_true(near(result, complex(710.0734104835082, 0.7853981633974483)))

    let axis = complex(-1.7e308, 0.0).log()
    try expect_true(near(axis, complex(709.7268368932282, 3.141592653589793)))
    try expect_true(near(complex(1.0, 0.0).log(), complex(0.0, 0.0)))

test "complex sqrt keeps a finite root for a subnormal input":
    let root = complex(0.0, 5.0e-324).sqrt()
    try expect_true(root.re > 0.0 and root.re.is_finite())
    try expect_true(root.im > 0.0 and root.im.is_finite())
    try expect_true(root.re / 1.5717277847026288e-162 > 0.999999999)
    try expect_true(root.re / 1.5717277847026288e-162 < 1.000000001)

    let below = complex(0.0, -5.0e-324).sqrt()
    try expect_true(below.re > 0.0 and below.im < 0.0)

// The small component needs relative checks: the ordinary near helper would
// accept zero here and conceal lost phase information.
test "complex tangent preserves huge finite phases":
    for phase in [1.0e308, -1.0e308]:
        let expected = if phase > 0.0: -3.948379522881268e-36 else: 3.948379522881268e-36

        for magnitude in [41.0, -41.0]:
            let tangent = complex(phase, magnitude).tan()
            try expect_true(tangent.re.is_finite())
            try expect_true((tangent.re / expected - 1.0).abs() < 1e-12)
            try expect_equal(tangent.im, if magnitude > 0.0: 1.0 else: -1.0)

            let hyperbolic = complex(magnitude, phase).tanh()
            try expect_true(hyperbolic.im.is_finite())
            try expect_true((hyperbolic.im / expected - 1.0).abs() < 1e-12)
            try expect_equal(hyperbolic.re, if magnitude > 0.0: 1.0 else: -1.0)

test "complex tangent handles the largest finite phase":
    let phase = 1.7976931348623157e308
    let expected = -4.847970089451913e-38
    let tangent = complex(phase, 41.0).tan()
    try expect_true((tangent.re / expected - 1.0).abs() < 1e-12)
    try expect_equal(tangent.im, 1.0)

    let hyperbolic = complex(41.0, phase).tanh()
    try expect_true((hyperbolic.im / expected - 1.0).abs() < 1e-12)
    try expect_equal(hyperbolic.re, 1.0)
