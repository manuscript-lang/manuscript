// conform: tags=decimal,formatter,interpolation,modules,optional,parser,stdlib-decimal,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/runtime-6.ms
import (
	Decimal from "@std/math/decimal.ms",
	expect_equal, expect_not_equal from "@std/test/test.ms",
)

fn quotient(value: Int, divisor: Int) Int:
	return value / divisor

fn remainder(value: Int, divisor: Int) Int:
	return value % divisor

test "numeric boundary rules":
	expect_equal(quotient(-7, 2), -3)?
	expect_equal(remainder(-7, 3), -1)?
	expect_equal(remainder(-9223372036854775808, -1), 0)?

	infinity := 1.0 / 0.0
	nan := 0.0 / 0.0
	expect_equal("{infinity}", "Infinity")?
	expect_not_equal(nan, nan)?

	third := 1d / 3d
	expect_equal("{third}", "0.3333333333333333333333333333333333")?

	absent: Int? := none
	expect_equal(1e300.truncate_to_int(), absent)?
	expect_equal((2.seconds() + 1.seconds()), 3.seconds())?
