// conform: tags=decimal,formatter,interpolation,modules,optional,parser,stdlib-decimal,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/runtime-6.ms
import (
	Decimal from "@std/math/decimal.ms",
	expect_equal, expect_not_equal from "@std/test/test.ms",
)

fn quotient(value Int, divisor Int) Int {
	return value / divisor
}

fn remainder(value Int, divisor Int) Int {
	return value % divisor
}

test "numeric boundary rules" {
	expect_equal(quotient(-7, 2), -3)?
	expect_equal(remainder(-7, 3), -1)?
	expect_equal(remainder(-9223372036854775808, -1), 0)?

	infinity := 1.0 / 0.0
	nan := 0.0 / 0.0
	expect_equal(f"{infinity}", "Infinity")?
	expect_not_equal(nan, nan)?

	third := 1d / 3d
	expect_equal(f"{third}", "0.3333333333333333333333333333333333")?

	absent Int? := null
	expect_equal(1e300.truncate_to_int(), absent)?
	expect_equal(2.seconds().add(1.seconds()), 3.seconds())?
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tDecimal from "@std/math/decimal.ms",
// expect-formatted: \texpect_equal, expect_not_equal from "@std/test/test.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: fn quotient(value, divisor Int) Int {
// expect-formatted: \treturn value / divisor
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn remainder(value, divisor Int) Int {
// expect-formatted: \treturn value % divisor
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "numeric boundary rules" {
// expect-formatted: \texpect_equal(quotient(-7, 2), -3)?
// expect-formatted: \texpect_equal(remainder(-7, 3), -1)?
// expect-formatted: \texpect_equal(remainder(-9223372036854775808, -1), 0)?
// expect-formatted:
// expect-formatted: \tinfinity := 1.0 / 0.0
// expect-formatted: \tnan := 0.0 / 0.0
// expect-formatted: \texpect_equal(f"{infinity}", "Infinity")?
// expect-formatted: \texpect_not_equal(nan, nan)?
// expect-formatted:
// expect-formatted: \tthird := 1d / 3d
// expect-formatted: \texpect_equal(f"{third}", "0.3333333333333333333333333333333333")?
// expect-formatted:
// expect-formatted: \tabsent Int? := null
// expect-formatted: \texpect_equal(1e300.truncate_to_int(), absent)?
// expect-formatted: \texpect_equal(2.seconds().add(1.seconds()), 3.seconds())?
// expect-formatted: }
