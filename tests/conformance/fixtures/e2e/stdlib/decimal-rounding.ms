// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Decimal, RoundingMode from "@std/math/decimal.ms",
	expect_equal from "@std/test/test.ms",
)

test "decimal cents stay exact and fixed places retain zeros":
	total := 19.99d * 3d
	tax := (total * 0.0825d).round(2)?
	expect_equal(tax, 4.95d)?
	expect_equal((tax.to_fixed(2)?), "4.95")?
	expect_equal(((total + tax).to_fixed(2)?), "64.92")?
	expect_equal((25.50d.to_fixed(2)?), "25.50")?
	expect_equal((9007199254740993.125d.to_fixed(2)?), "9007199254740993.12")?
	expect_equal("{25.50d}", "25.5")?
	expect_equal(1d / 3d, 0.3333333333333333333333333333333333d)?

test "decimal rounding modes include signed ties and coarse scales":
	expect_equal((2.5d.round(0, none)?), 2d)?
	expect_equal((3.5d.round(0)?), 4d)?
	expect_equal(((-2.5d).round(0)?), -2d)?
	expect_equal(((-2.5d).round(0, RoundingMode.HalfAwayFromZero)?), -3d)?
	expect_equal(((-2.9d).round(0, RoundingMode.TowardZero)?), -2d)?
	expect_equal(((-2.1d).round(0, RoundingMode.Floor)?), -3d)?
	expect_equal(((-2.1d).round(0, RoundingMode.Ceil)?), -2d)?
	expect_equal((1250d.round(-2)?), 1200d)?
	expect_equal(((-0.005d).to_fixed(2)?), "0.00")?
	expect_equal(((-0.005d).to_fixed(2, RoundingMode.Floor)?), "-0.01")?

	fixed := 25.5d.to_fixed
	expect_equal((fixed(2)?), "25.50")?

	rounded: fn(Int, RoundingMode?) Decimal! := 2.5d.round
	expect_equal((rounded(0, RoundingMode.HalfEven)?), 2d)?

test "decimal scale extremes and invalid requests return typed errors":
	expect_equal((1e-6176d.round(6176)?), 1e-6176d)?
	expect_equal((5e-6176d.round(6175)?), 0d)?
	expect_equal((1e6144d.round(-6144)?), 1e6144d)?
	expect_equal((0d.to_fixed(6176)?).scalar_length(), 6178)?

	invalid_round: Decimal! := error(Error("number: invalid input", kind: "EINVAL"))
	expect_equal(0d.round(-6145), invalid_round)?
	expect_equal(0d.round(6177), invalid_round)?

	invalid_fixed: String! := error(Error("number: invalid input", kind: "EINVAL"))
	expect_equal(0d.to_fixed(-1), invalid_fixed)?
	expect_equal(0d.to_fixed(6177), invalid_fixed)?

	overflow: Decimal! := error(Error("number: value out of range", kind: "ERANGE"))
	expect_equal(9.999999999999999999999999999999999e6144d.round(-6144), overflow)?

test "exact rounding retains values at every supported precision":
	for mode in [
		RoundingMode.HalfEven,
		RoundingMode.HalfAwayFromZero,
		RoundingMode.TowardZero,
		RoundingMode.Floor,
		RoundingMode.Ceil,
	]:
		for value in [0d, 1.25d, -1.25d, 1e6144d, -1e6144d]:
			expect_equal((value.round(6176, mode)?), value)?
		expect_equal((0d.round(-6144, mode)?), 0d)?
		expect_equal(((-1e-6176d).round(6176, mode)?), -1e-6176d)?
