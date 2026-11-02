import expect_equal, expect_true from "@std/test/test.ms"
import (
    BigRat,
    BigRatError,
    BigFloat,
    BigFloatError,
    parse_rat,
    rat,
    rat_of_float,
    rat_of_int,
    big_float_of_int,
    big_float_of_float,
    parse_big_float
) from "@std/math/big.ms"
import from_int from "@std/math/math.ms"

test "rationals stay in lowest terms and compare with ==":
    let half = try parse_rat("1/2")
    let third = try parse_rat("1/3")
    try expect_equal(half.add(third).format(), "5/6")
    try expect_equal(half.subtract(third).format(), "1/6")
    try expect_equal(half.multiply(third).format(), "1/6")
    try expect_equal((try half.divide(third)).format(), "3/2")
    try expect_equal(try parse_rat("2/4"), half)
    try expect_equal(try parse_rat("-3/-6"), half)
    try expect_equal((try parse_rat("3/-6")).format(), "-1/2")
    try expect_equal(half.compare(third), 1)
    try expect_true(rat_of_int(4).is_integer())
    try expect_equal(rat_of_int(4).format(), "4")

test "rational errors and decimal parsing":
    let zero: BigRat!BigRatError = error(BigRatError.InvalidInput)
    try expect_equal(rat(from_int(1), from_int(0)), zero)
    try expect_equal(rat_of_int(1).divide(rat_of_int(0)), zero)

    let bad: BigRat!BigRatError = error(BigRatError.InvalidData)
    try expect_equal(parse_rat("1/2/3"), bad)
    try expect_equal(parse_rat("abc"), bad)
    try expect_equal(parse_rat("1.2.3"), bad)

    let big: BigRat!BigRatError = error(BigRatError.LimitExceeded)
    try expect_equal(parse_rat("1e100001"), big)
    try expect_equal((try parse_rat("1.25")).format(), "5/4")
    try expect_equal((try parse_rat("-.5")).format(), "-1/2")
    try expect_equal((try parse_rat("6.02e3")).format(), "6020")
    try expect_equal((try parse_rat("5E-3")).format(), "1/200")

test "rational rounding power and formatting":
    let value = try parse_rat("-7/2")
    try expect_equal(value.floor().to_int(), -4)
    try expect_equal(value.ceil().to_int(), -3)
    try expect_equal(value.truncate().to_int(), -3)
    try expect_equal(value.round().to_int(), -4)
    try expect_equal((try parse_rat("5/2")).round().to_int(), 3)

    let two_thirds = try parse_rat("2/3")
    try expect_equal((try two_thirds.pow(3)).format(), "8/27")
    try expect_equal((try two_thirds.pow(-2)).format(), "9/4")
    try expect_equal(try two_thirds.to_fixed(4), "0.6667")
    try expect_equal(try (try parse_rat("1/8")).to_fixed(2), "0.12")
    try expect_equal(try (try parse_rat("3/8")).to_fixed(2), "0.38")
    try expect_equal(try (try parse_rat("-1/1000")).to_fixed(2), "0.00")
    try expect_equal(try (try parse_rat("-5/2")).to_fixed(0), "-2")
    try expect_equal(try (try parse_rat("1/3")).to_fixed(3), "0.333")

test "rationals convert exactly from and to floats":
    let tenth = rat_of_float(0.1).get(rat_of_int(0))
    try expect_equal(tenth.format(), "3602879701896397/36028797018963968")
    try expect_equal(tenth.to_float(), 0.1)
    try expect_true(rat_of_float(1.0 / 0.0).is_none())
    try expect_equal(rat_of_float(-2.5).get(rat_of_int(0)).format(), "-5/2")
    try expect_equal((try parse_rat("1/3")).to_float(), 1.0 / 3.0)
    try expect_equal(rat_of_float(1e300).get(rat_of_int(0)).to_float(), 1e300)

test "big floats round once at their precision":
    let two = big_float_of_int(2, 200)
    let root = try two.sqrt()
    try expect_equal(
        try root.to_fixed(40), "1.4142135623730950488016887242096980785697"
    )

    let error_bound = try parse_big_float("1e-55", 200)
    try expect_equal(root.multiply(root).subtract(two).abs().compare(error_bound), -1)
    try expect_equal(
        try (
            try big_float_of_int(1, 100).divide(big_float_of_int(3, 100))
        ).to_fixed(30),
        "0.333333333333333333333333333333"
    )
    try expect_equal(
        (try big_float_of_int(2, 53).sqrt()).to_float(), 1.4142135623730951
    )
    try expect_equal(big_float_of_int(7, 10).precision(), 10)
    try expect_equal(big_float_of_int(1000, 100).with_precision(3).to_float(), 1024.0)

test "big floats add, subtract and compare across magnitudes":
    let tenth = try parse_big_float("0.1", 120)
    let sum = tenth.add(tenth).add(tenth)
    try expect_equal(try sum.to_fixed(25), "0.3000000000000000000000000")

    let huge = try parse_big_float("1e1000", 64)
    let tiny = big_float_of_int(1, 64)
    try expect_equal(huge.add(tiny).compare(huge), 0)
    try expect_equal(huge.subtract(tiny).compare(huge), 0)
    try expect_equal(huge.negate().add(tiny).compare(huge.negate()), 0)
    try expect_equal(huge.compare(tiny), 1)
    try expect_equal(
        big_float_of_int(5, 64).subtract(big_float_of_int(5, 64)).sign(), 0
    )
    try expect_equal(big_float_of_float(0.5, 53).get(tiny).add(tiny).to_float(), 1.5)
    try expect_equal(
        big_float_of_int(-7, 64).divide(big_float_of_int(2, 64)).get(
            tiny
        ).truncate().to_int(),
        -3
    )

test "big float errors":
    let zero: BigFloat!BigFloatError = error(BigFloatError.InvalidInput)
    try expect_equal(big_float_of_int(1, 64).divide(big_float_of_int(0, 64)), zero)
    try expect_equal(big_float_of_int(-1, 64).sqrt(), zero)

    let bad: BigFloat!BigFloatError = error(BigFloatError.InvalidData)
    try expect_equal(parse_big_float("x", 64), bad)
    try expect_equal(parse_big_float("1/2", 64), bad)

    let limit: BigFloat!BigFloatError = error(BigFloatError.LimitExceeded)
    try expect_equal(parse_big_float("1e999999", 64), limit)
    try expect_true(big_float_of_float(0.0 / 0.0, 64).is_none())
