import expect_equal, expect_true from "@std/test/test.ms"
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
