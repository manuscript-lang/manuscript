import (
	parse_float from "@std/math/math.ms",
	expect_equal from "@std/test/test.ms",
)

test "float parsing keeps ASCII signs decimals and exponents":
	for text in ["1.25", "+1.25", "125e-2", "0.125E+1"]:
		expect_equal(text.parse_float().get(), 1.25)?
		expect_equal((parse_float(text)?), 1.25)?

	expect_equal("-0".parse_float().get().to_string(), "-0")?
	expect_equal((parse_float("-0")?).to_string(), "-0")?

test "float parsing rejects Unicode syntax and malformed or overflowing text":
	invalid: Float! := error(Error("number: invalid data", kind: "EBADMSG"))

	for text in ["١", "１", "1.٢", "1e٣", "−1", "1 ", ".5", "1.", "1e+", " 1", "1_0"]:
		expect_equal(text.parse_float(), none)?
		expect_equal(parse_float(text), invalid)?

	expect_equal("1e400".parse_float(), none)?

	overflow: Float! := error(Error("number: value out of range", kind: "ERANGE"))
	expect_equal(parse_float("1e400"), overflow)?

	huge := "9".repeat(4096).get()
	expect_equal(huge.parse_float(), none)?
	expect_equal(parse_float(huge), overflow)?
	expect_equal(parse_float("{huge}!"), invalid)?
