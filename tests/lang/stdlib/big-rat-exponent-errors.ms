// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	parse_big_float, parse_rat from "@std/math/big.ms",
	expect_equal from "@std/test/test.ms",
)

test "big rational oversized decimal exponents are limit errors" {
	for exponent in [
		"100001", "-100001", "-1000001", "9223372036854775807", "-9223372036854775808",
		"9223372036854775808", "-9223372036854775809",
		"+999999999999999999999999999999", "-999999999999999999999999999999"
	] {
		expect_equal(parse_rat(f"1e{exponent}").err().kind, "EOVERFLOW")?
		expect_equal(parse_big_float(f"1e{exponent}", 53).err().kind, "EOVERFLOW")?
	}
}

test "big rational malformed exponents stay data errors even after many digits" {
	for exponent in [
		"", "+", "--1", "+-1", "1_0", "999999999999999999999999999999x",
		"-999999999999999999999999999999 ", "１２"
	] {
		expect_equal(parse_rat(f"1e{exponent}").err().kind, "EBADMSG")?
		expect_equal(parse_big_float(f"1e{exponent}", 53).err().kind, "EBADMSG")?
	}

	expect_equal((parse_rat("1e+0002")?).to_string(), "100")?
	expect_equal((parse_rat("1e-0002")?).to_string(), "1/100")?
}

test "big rational exponent limits remain inclusive" {
	expect_equal((parse_rat("0e100000")?).to_string(), "0")?
	expect_equal((parse_rat("0e-100000")?).to_string(), "0")?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
