# conform: tags=decimal,modules,optional,stdlib-decimal,stdlib-math,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/decimal-math.ms
import expect_equal, expect_false from "@std/test/test.ms"
import Decimal from "@std/math/decimal.ms"
import (
    ceil,
    floor,
    round,
    truncate,
    sqrt,
    hypot,
    pow,
    log2,
    min,
    max,
    sin,
    cos,
    pi
) from "@std/math/math.ms"

test "decimal arithmetic is exact and conversion truncates":
    try expect_equal(0.1d + 0.2d, 0.3d)
    try expect_equal(1.00d, 1d)
    try expect_equal((-1.9d).truncate_to_int(), -1)
    try expect_equal(2d.to_float(), 2.0)
    try expect_equal(1e400d.to_float(), none)
    try expect_equal(123.to_decimal(), 123d)

test "math rounding signs and exact identities":
    try expect_false((-2.5).abs() != 2.5 or (-3).abs() != 3)
    try expect_false(ceil(-1.5) != -1.0 or floor(-1.5) != -2.0)
    try expect_false(round(2.5) != 3.0 or truncate(-1.9) != -1.0)
    try expect_false(sqrt(9.0) != 3.0 or hypot(3.0, 4.0) != 5.0)
    try expect_false(pow(2.0, 3.0) != 8.0 or log2(8.0) != 3.0)
    try expect_false(min(2.0, 3.0) != 2.0 or max(2.0, 3.0) != 3.0)
    try expect_false((sin(0.0) != 0.0 or cos(0.0) != 1.0 or pi < 3.14))
    try expect_false(not sqrt(-1.0).is_nan())
