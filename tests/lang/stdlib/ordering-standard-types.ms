// conform: tags=stdlib-time,stdlib-math,testing
// conform: phase=test
import (
	Decimal from "@std/math/decimal.ms",
	big_int_of_int from "@std/math/math.ms",
	expect_equal from "@std/test/test.ms",
	parse_timestamp, seconds from "@std/time.ms",
)

test "Duration orders with min, max and clamp" {
	expect_equal(seconds(3).min(seconds(5)), seconds(3))?
	expect_equal(seconds(3).max(seconds(5)), seconds(5))?
	expect_equal(seconds(9).clamp(seconds(1), seconds(5)), seconds(5))?
	expect_equal(seconds(-9).clamp(seconds(1), seconds(5)), seconds(1))?
	expect_equal(seconds(3).clamp(seconds(1), seconds(5)), seconds(3))?
}

test "Timestamp orders with min, max and clamp" {
	early := parse_timestamp("2024-01-01T00:00:00Z").get()
	late := parse_timestamp("2025-01-01T00:00:00Z").get()
	expect_equal(early.min(late).to_string(), "2024-01-01T00:00:00Z")?
	expect_equal(early.max(late).to_string(), "2025-01-01T00:00:00Z")?
	expect_equal(early.clamp(late, late).to_string(), "2025-01-01T00:00:00Z")?
}

test "Decimal orders with min, max and clamp" {
	a := (150).to_decimal()
	b := (7).to_decimal()
	expect_equal(a.min(b).to_fixed(0, null).get(), "7")?
	expect_equal(a.max(b).to_fixed(0, null).get(), "150")?
	expect_equal(a.clamp(b, b).to_fixed(0, null).get(), "7")?
}

test "BigInt orders with min, max and clamp" {
	expect_equal(big_int_of_int(-4).min(big_int_of_int(2)).to_string(), "-4")?
	expect_equal(big_int_of_int(-4).max(big_int_of_int(2)).to_string(), "2")?
	expect_equal(
		big_int_of_int(40).clamp(
			big_int_of_int(1),
			big_int_of_int(5),
		).to_string(),
		"5",
	)?
}
