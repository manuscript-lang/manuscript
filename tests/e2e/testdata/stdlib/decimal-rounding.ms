import {expect_equal, expect_ok} from "@std/testing.ms"
import {Decimal, RoundingMode} from "@std/decimal.ms"
import NumberError from "@std/numbers.ms"

test "decimal cents stay exact and fixed places retain zeros":
    let total = 19.99d * 3d
    let tax = ((total * 0.0825d).round(places: 2) | try expect_ok)
    tax | try expect_equal(expected: 4.95d)
    tax.to_fixed(digits: 2) | try expect_ok | try expect_equal(expected: "4.95")
    (total + tax).to_fixed(digits: 2) | try expect_ok | try expect_equal(
        expected: "64.92"
    )
    25.50d.to_fixed(digits: 2) | try expect_ok | try expect_equal(expected: "25.50")
    9007199254740993.125d.to_fixed(digits: 2) | try expect_ok | try expect_equal(
        expected: "9007199254740993.12"
    )
    "{25.50d}" | try expect_equal(expected: "25.5")
    (1d / 3d) | try expect_equal(expected: 0.3333333333333333333333333333333333d)

test "decimal rounding modes include signed ties and coarse scales":
    2.5d.round(places: 0, mode: none) | try expect_ok | try expect_equal(expected: 2d)
    3.5d.round(places: 0) | try expect_ok | try expect_equal(expected: 4d)
    (-2.5d).round(places: 0) | try expect_ok | try expect_equal(expected: -2d)
    (-2.5d).round(places: 0, mode: RoundingMode.HalfAwayFromZero) | try expect_ok | try expect_equal(
        expected: (-3d)
    )
    (-2.9d).round(places: 0, mode: RoundingMode.TowardZero) | try expect_ok | try expect_equal(
        expected: -2d
    )
    (-2.1d).round(places: 0, mode: RoundingMode.Floor) | try expect_ok | try expect_equal(
        expected: (-3d)
    )
    (-2.1d).round(places: 0, mode: RoundingMode.Ceil) | try expect_ok | try expect_equal(
        expected: (-2d)
    )
    1250d.round(places: -2) | try expect_ok | try expect_equal(expected: 1200d)
    (-0.005d).to_fixed(digits: 2) | try expect_ok | try expect_equal(expected: "0.00")
    (-0.005d).to_fixed(digits: 2, mode: RoundingMode.Floor) | try expect_ok | try expect_equal(
        expected: "-0.01"
    )
    let fixed = 25.5d.to_fixed
    fixed(digits: 2) | try expect_ok | try expect_equal(expected: "25.50")
    let rounded: fn(places: Int, mode: Optional[RoundingMode]) -> Result[
        Decimal,
        NumberError
    ] = 2.5d.round
    rounded(places: 0, mode: RoundingMode.HalfEven) | try expect_ok | try expect_equal(
        expected: 2d
    )

test "decimal scale extremes and invalid requests return typed errors":
    1e-6176d.round(places: 6176) | try expect_ok | try expect_equal(expected: 1e-6176d)
    5e-6176d.round(places: 6175) | try expect_ok | try expect_equal(expected: 0d)
    1e6144d.round(places: -6144) | try expect_ok | try expect_equal(expected: 1e6144d)
    (0d.to_fixed(digits: 6176) | try expect_ok).scalar_length() | try expect_equal(
        expected: 6178
    )
    let invalid_round: Result[Decimal, NumberError] = error(NumberError.InvalidInput)
    0d.round(places: -6145) | try expect_equal(expected: invalid_round)
    0d.round(places: 6177) | try expect_equal(expected: invalid_round)
    let invalid_fixed: Result[String, NumberError] = error(NumberError.InvalidInput)
    0d.to_fixed(digits: -1) | try expect_equal(expected: invalid_fixed)
    0d.to_fixed(digits: 6177) | try expect_equal(expected: invalid_fixed)
    let overflow: Result[Decimal, NumberError] = error(NumberError.OutOfRange)
    9.999999999999999999999999999999999e6144d.round(places: -6144) | try expect_equal(
        expected: overflow
    )
