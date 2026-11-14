// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Decimal, parse_decimal from "@std/math/decimal.ms",
	expect_equal from "@std/test/test.ms",
)

test "parse_decimal reads exact decimal text":
	expect_equal(parse_decimal("19.99")?, 19.99d)?
	expect_equal(parse_decimal("-0.5")?, -0.5d)?
	expect_equal(parse_decimal("1e3")?, 1000d)?
	expect_equal(parse_decimal("+7")?, 7d)?
	expect_equal((parse_decimal("007.50")?).to_string(), "7.5")?
	expect_equal(parse_decimal("0.1")? + parse_decimal("0.2")?, 0.3d)?

test "parse_decimal rejects text that is not exactly a Decimal":
	for text in ["", " 1", "1.", ".5", "abc", "1e", "1_0", "12345678901234567890123456789012345"]:
		parsed := parse_decimal(text)
		expect_equal(parsed.is_error(), true)?
		expect_equal(parsed.err().kind, "EINVAL")?
