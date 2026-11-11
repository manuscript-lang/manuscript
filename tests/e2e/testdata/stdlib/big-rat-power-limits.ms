import (
	parse_rat, rat_of_int from "@std/math/big.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

// 2^16777216 has 16777217 bits. BigInt rejects it from its lower size
// bound without computing the oversized power.
test "rational powers preserve numerator and denominator size errors":
	for text in ["2", "-2", "1/2", "-1/2", "2/3"]:
		value := parse_rat(text)?

		for exponent in [16777216, -16777216]:
			failure := expect_error(value.pow(exponent))?
			expect_equal(failure.kind, "EOVERFLOW")?

test "rational powers retain exact ordinary results":
	value := parse_rat("-2/3")?
	expect_equal((value.pow(3)?).format(), "-8/27")?
	expect_equal((value.pow(-3)?).format(), "-27/8")?
	expect_equal((value.pow(0)?).format(), "1")?

test "rational powers retain zero and unit controls":
	zero := rat_of_int(0)
	expect_equal((zero.pow(0)?).format(), "1")?
	expect_equal((zero.pow(16777216)?).format(), "0")?
	expect_equal((expect_error(zero.pow(-1))?).kind, "EINVAL")?

	for exponent in [16777216, -16777216, 16777217, -16777217]:
		expect_equal((rat_of_int(1).pow(exponent)?).format(), "1")?

		expected := if exponent % 2 == 0: "1" else: "-1"
		expect_equal((rat_of_int(-1).pow(exponent)?).format(), expected)?

test "rational powers accept the minimum Int exponent for unit and zero bases":
	least := -9223372036854775807 - 1
	expect_equal((rat_of_int(1).pow(least)?).format(), "1")?
	expect_equal((rat_of_int(-1).pow(least)?).format(), "1")?
	expect_equal((rat_of_int(-1).pow(least + 1)?).format(), "-1")?
	expect_equal((expect_error(rat_of_int(0).pow(least))?).kind, "EINVAL")?
	expect_equal((expect_error(rat_of_int(2).pow(least))?).kind, "EOVERFLOW")?
	expect_equal(
		(expect_error(rat_of_int(2).pow(9223372036854775807))?).kind, "EOVERFLOW"
	)?
