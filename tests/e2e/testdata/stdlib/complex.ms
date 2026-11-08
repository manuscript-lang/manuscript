import expect_equal, expect_true from "@std/test/test.ms"
import infinity from "@std/math/math.ms"
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

// Reference values use the exact binary64 inputs before high-precision square root/log.
type ComplexRangeCase:
    value: Complex
    root: Complex
    logarithm: Float

test "complex roots and logarithms preserve finite range information":
    for sample in [
        ComplexRangeCase(
            complex(0.0, 5e-324),
            complex(1.5717277847026288e-162, 1.5717277847026288e-162),
            -744.4400719213812
        ),
        ComplexRangeCase(
            complex(5e-324, 5e-324),
            complex(2.4421097261308304e-162, 1.0115549693666347e-162),
            -744.0934983311013
        ),
        ComplexRangeCase(
            complex(-5e-324, 5e-324),
            complex(1.0115549693666347e-162, 2.4421097261308304e-162),
            -744.0934983311013
        ),
        ComplexRangeCase(
            complex(1.5e-323, 2e-323),
            complex(4.445517498970155e-162, 2.2227587494850775e-162), -742.8306340089472
        ),
        ComplexRangeCase(
            complex(2.2250738585072014e-308, 5e-324),
            complex(1.4916681462400413e-154, 1.656084321055619e-170), -708.3964185322641
        ),
        ComplexRangeCase(
            complex(1.1125369292536007e-308, 1.1125369292536007e-308),
            complex(1.158857571758704e-154, 4.800145230812074e-155), -708.742992122544
        ),
        ComplexRangeCase(
            complex(1.7976931348623157e308, 1.7976931348623157e308),
            complex(1.4730945569055652e154, 6.1017574412827024e153), 710.1292864836639
        ),
        ComplexRangeCase(
            complex(-1.7976931348623157e308, 1.7976931348623157e308),
            complex(6.1017574412827024e153, 1.4730945569055652e154), 710.1292864836639
        )
    ]:
        for sign in [-1.0, 1.0]:
            let value = complex(sample.value.re, sign * sample.value.im)
            let root = value.sqrt()
            try expect_true((root.re / sample.root.re - 1.0).abs() < 2e-14)
            try expect_true((root.im / (sign * sample.root.im) - 1.0).abs() < 2e-14)

            let logarithm = value.log()
            try expect_true((logarithm.re - sample.logarithm).abs() < 1e-12)
            try expect_equal(logarithm.im, value.phase())

test "complex range repairs retain signed zeros and nonfinite behavior":
    for zero in [0.0, -0.0]:
        let positive = complex(4.0, zero).sqrt()
        try expect_equal(positive.re, 2.0)
        try expect_equal(1.0 / positive.im, 1.0 / zero)

        let negative = complex(-4.0, zero).sqrt()
        try expect_equal(1.0 / negative.re, infinity)
        try expect_equal(negative.im, if 1.0 / zero < 0.0: -2.0 else: 2.0)

        let origin = complex(0.0, zero).log()
        try expect_equal(origin.re, -infinity)
        try expect_equal(1.0 / origin.im, 1.0 / zero)

    let nan = 0.0 / 0.0
    try expect_true(complex(nan, 1.0).sqrt().is_nan())
    try expect_true(complex(1.0, nan).log().is_nan())
    try expect_equal(complex(infinity, 1.0).sqrt(), complex(infinity, 0.0))
    try expect_equal(complex(-infinity, 1.0).sqrt(), complex(0.0, infinity))
    try expect_equal(complex(infinity, 1.0).log().re, infinity)
    try expect_true(complex(1.0, infinity).sqrt().im.is_nan())
