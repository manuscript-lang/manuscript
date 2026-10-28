from "@std/test.ms" import expect_equal
from "@std/decimal.ms" import Decimal, RoundingMode
from "@std/math.ms" import NumberError

test "decimal cents stay exact and fixed places retain zeros":
    let total = 19.99d * 3d
    let tax = try (total * 0.0825d).round(2)
    try expect_equal(tax, 4.95d)
    try expect_equal((try tax.to_fixed(2)), "4.95")
    try expect_equal((try (total + tax).to_fixed(2)), "64.92")
    try expect_equal((try 25.50d.to_fixed(2)), "25.50")
    try expect_equal((try 9007199254740993.125d.to_fixed(2)), "9007199254740993.12")
    try expect_equal(f"{25.50d}", "25.5")
    try expect_equal(1d / 3d, 0.3333333333333333333333333333333333d)

test "decimal rounding modes include signed ties and coarse scales":
    try expect_equal((try 2.5d.round(0, none)), 2d)
    try expect_equal((try 3.5d.round(0)), 4d)
    try expect_equal((try (-2.5d).round(0)), -2d)
    try expect_equal((try (-2.5d).round(0, RoundingMode.HalfAwayFromZero)), -3d)
    try expect_equal((try (-2.9d).round(0, RoundingMode.TowardZero)), -2d)
    try expect_equal((try (-2.1d).round(0, RoundingMode.Floor)), -3d)
    try expect_equal((try (-2.1d).round(0, RoundingMode.Ceil)), -2d)
    try expect_equal((try 1250d.round(-2)), 1200d)
    try expect_equal((try (-0.005d).to_fixed(2)), "0.00")
    try expect_equal((try (-0.005d).to_fixed(2, RoundingMode.Floor)), "-0.01")

    let fixed = 25.5d.to_fixed
    try expect_equal((try fixed(2)), "25.50")

    let rounded: Callable[[Int, Optional[RoundingMode]], Result[Decimal, NumberError]] = 2.5d.round
    try expect_equal((try rounded(0, RoundingMode.HalfEven)), 2d)

test "decimal scale extremes and invalid requests return typed errors":
    try expect_equal((try 1e-6176d.round(6176)), 1e-6176d)
    try expect_equal((try 5e-6176d.round(6175)), 0d)
    try expect_equal((try 1e6144d.round(-6144)), 1e6144d)
    try expect_equal((try 0d.to_fixed(6176)).scalar_length(), 6178)

    let invalid_round: Result[Decimal, NumberError] = error(NumberError.InvalidInput)
    try expect_equal(0d.round(-6145), invalid_round)
    try expect_equal(0d.round(6177), invalid_round)

    let invalid_fixed: Result[String, NumberError] = error(NumberError.InvalidInput)
    try expect_equal(0d.to_fixed(-1), invalid_fixed)
    try expect_equal(0d.to_fixed(6177), invalid_fixed)

    let overflow: Result[Decimal, NumberError] = error(NumberError.OutOfRange)
    try expect_equal(9.999999999999999999999999999999999e6144d.round(-6144), overflow)

test "exact rounding retains values at every supported precision":
    for mode in [
        RoundingMode.HalfEven, RoundingMode.HalfAwayFromZero, RoundingMode.TowardZero,
        RoundingMode.Floor, RoundingMode.Ceil
    ]:
        for value in [0d, 1.25d, -1.25d, 1e6144d, -1e6144d]:
            try expect_equal((try value.round(6176, mode)), value)
        try expect_equal((try 0d.round(-6144, mode)), 0d)
        try expect_equal((try (-1e-6176d).round(6176, mode)), -1e-6176d)
