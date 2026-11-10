import (
	parse_rat, parse_big_float from "@std/math/big.ms",
	expect_equal from "@std/test/test.ms",
)

test "big rational oversized decimal exponents are limit errors":
	for exponent in [
		"100001", "-100001", "-1000001", "9223372036854775807", "-9223372036854775808",
		"9223372036854775808", "-9223372036854775809",
		"+999999999999999999999999999999", "-999999999999999999999999999999"
	]:
		try expect_equal(parse_rat("1e{exponent}").err().kind, "EOVERFLOW")
		try expect_equal(parse_big_float("1e{exponent}", 53).err().kind, "EOVERFLOW")

test "big rational malformed exponents stay data errors even after many digits":
	for exponent in [
		"", "+", "--1", "+-1", "1_0", "999999999999999999999999999999x",
		"-999999999999999999999999999999 ", "１２"
	]:
		try expect_equal(parse_rat("1e{exponent}").err().kind, "EBADMSG")
		try expect_equal(parse_big_float("1e{exponent}", 53).err().kind, "EBADMSG")

	try expect_equal((try parse_rat("1e+0002")).format(), "100")
	try expect_equal((try parse_rat("1e-0002")).format(), "1/100")

test "big rational exponent limits remain inclusive":
	try expect_equal((try parse_rat("0e100000")).format(), "0")
	try expect_equal((try parse_rat("0e-100000")).format(), "0")
