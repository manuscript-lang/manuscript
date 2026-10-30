import expect_equal, expect_false from "@std/test.ms"
import Decimal from "@std/decimal.ms"
import ceil, floor, round, truncate, sqrt, hypot, pow, log2, min, max, sin, cos, pi from "@std/math.ms"

test "decimal arithmetic is exact and conversion truncates":
    try expect_equal(0.1d + 0.2d, 0.3d)
    try expect_equal(1.00d, 1d)
    try expect_equal((-1.9d).truncate_to_int(), some(-1))
    try expect_equal(2d.to_float(), some(2.0))
    try expect_equal(1e400d.to_float(), none)
    try expect_equal(123.to_decimal(), 123d)

test "decimal integer conversions normalize boundary values":
    let minimum: Int = -9223372036854775808
    let maximum: Int = 9223372036854775807
    let unsigned: UInt64 = 18446744073709551615
    let power: UInt64 = 10000000000000000000
    try expect_equal(minimum.to_decimal(), -9223372036854775808d)
    try expect_equal(maximum.to_decimal(), 9223372036854775807d)
    try expect_equal(unsigned.to_decimal(), 18446744073709551615d)
    try expect_equal(power.to_decimal(), 1e19d)
    try expect_equal((-1000000000000000000).to_decimal(), -1e18d)
    try expect_equal(0.to_decimal(), 0d)

test "decimal negation keeps full precision and exponent":
    let maximum = 9.999999999999999999999999999999999e6144d
    let minimum = 1e-6176d
    try expect_equal(-maximum, -9.999999999999999999999999999999999e6144d)
    try expect_equal(-(-maximum), maximum)
    try expect_equal(-minimum, -1e-6176d)
    try expect_equal(-(-minimum), minimum)
    try expect_equal(-0d, 0d)

test "math rounding signs and exact identities":
    try expect_false((-2.5).abs() != 2.5 or (-3).abs() != 3)
    try expect_false(ceil(-1.5) != -1.0 or floor(-1.5) != -2.0)
    try expect_false(round(2.5) != 3.0 or truncate(-1.9) != -1.0)
    try expect_false(sqrt(9.0) != 3.0 or hypot(3.0, 4.0) != 5.0)
    try expect_false(pow(2.0, 3.0) != 8.0 or log2(8.0) != 3.0)
    try expect_false(min(2.0, 3.0) != 2.0 or max(2.0, 3.0) != 3.0)
    try expect_false((sin(0.0) != 0.0 or cos(0.0) != 1.0 or pi() < 3.14))
    try expect_false(not sqrt(-1.0).is_nan())
