// conform: tags=control-flow,modules,numbers,optional,stdlib-numbers,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/stdlib/numbers.ms
import (
	parse_float, parse_int from "@std/math/math.ms",
	expect_equal from "@std/test/test.ms",
)

test "numbers radix and signed boundaries":
	expect_equal((parse_int("7fffffffffffffff", 16)?), 9223372036854775807)?
	expect_equal((parse_int("-9223372036854775808", 10)?), -9223372036854775808)?
	expect_equal(255.to_string_radix(16), "ff")?
	expect_equal((parse_float("-1.25e2")?), -125.0)?
	expect_equal(1.25.to_fixed(2), "1.25")?
	expect_equal(1.9.truncate_to_int(), 1)?

test "numbers reject whitespace separators overflow and invalid radix":
	invalid: Int! := error(Error("number: invalid data", kind: "EBADMSG"))
	for text in [" 1", "1_0", "0x10", "+", "١"]:
		expect_equal(parse_int(text, 10), invalid)?

	overflow: Int! := error(Error("number: value out of range", kind: "ERANGE"))
	expect_equal(parse_int("9223372036854775808", 10), overflow)?

	radix_error: Int! := error(Error("number: invalid input", kind: "EINVAL"))
	expect_equal(parse_int("1", 1), radix_error)?

	float_error: Float! := error(Error("number: invalid data", kind: "EBADMSG"))
	for text in [" 1.0", "1_0", "1.", "0x1p2"]:
		expect_equal(parse_float(text), float_error)?
