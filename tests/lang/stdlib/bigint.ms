// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	BigInt, big_int_of_int, parse_big_int from "@std/math/math.ms",
	expect_equal, expect_false, fail from "@std/test/test.ms",
)

test "big integers exceed machine range without losing precision" {
	big := parse_big_int("9223372036854775808", 10)?
	expect_false(big.to_int() != null)?
	expect_equal(big.subtract(big_int_of_int(1)).to_int(), 9223372036854775807)?
	expect_equal(big_int_of_int(7).multiply(big_int_of_int(6)).to_string(), "42")?
	expect_equal((big_int_of_int(-7).divide(big_int_of_int(3))?).to_int(), -2)?
	expect_equal((big_int_of_int(-7).remainder(big_int_of_int(3))?).to_int(), -1)?
	expect_equal(big_int_of_int(5).bit_xor(big_int_of_int(3)).to_int(), 6)?
}

test "big integers validate digits budgets and zero divisors" {
	invalid BigInt! := error(Error("big integer: invalid input", kind: "EINVAL"))
	expect_equal(big_int_of_int(1).divide(big_int_of_int(0)), invalid)?

	limited BigInt! := error(Error("big integer: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(parse_big_int("123", 10, 2), limited)?

	malformed BigInt! := error(Error("big integer: invalid data", kind: "EBADMSG"))
	expect_equal(parse_big_int("1_0", 10), malformed)?
}

test "big integer budgets exclude at most one leading sign before validation" {
	limited BigInt! := error(Error("big integer: limit exceeded", kind: "EOVERFLOW"))
	malformed BigInt! := error(Error("big integer: invalid data", kind: "EBADMSG"))

	for text in ["+-1", "-+1", "++1", "--1"] {
		if parse_big_int(text, 10, 1) != limited {
			return fail(f"second sign must count toward budget: {text}")
		}
		if parse_big_int(text, 10, 2) != malformed {
			return fail(f"second sign must fail syntax validation: {text}")
		}
	}

	for text in ["1", "+1", "-1"] {
		expect_false(parse_big_int(text, 10, 1).is_error())?
		expect_equal(parse_big_int(text, 10, 0), limited)?
	}
}

test "big integers support sign pow shifts and conversion" {
	five := big_int_of_int(5)
	expect_equal(five.negate().to_int(), -5)?
	expect_equal(five.negate().abs().to_int(), 5)?
	expect_equal(five.negate().sign(), -1)?
	expect_equal(big_int_of_int(0).sign(), 0)?
	expect_equal(five.bit_not().to_int(), -6)?
	expect_equal(
		(big_int_of_int(2).pow(100)?).to_string(),
		"1267650600228229401496703205376",
	)?
	expect_equal((five.shift_left(3)?).to_int(), 40)?
	expect_equal((big_int_of_int(-5).shift_right(1)?).to_int(), -3)?
	expect_equal(
		(big_int_of_int(1).shift_left(70)?).to_float(),
		1180591620717411303424.0,
	)?

	invalid BigInt! := error(Error("big integer: invalid input", kind: "EINVAL"))
	expect_equal(five.pow(-1), invalid)?
	expect_equal(five.shift_left(-1), invalid)?

	limited BigInt! := error(Error("big integer: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(big_int_of_int(2).pow(100000000), limited)?
	expect_equal(five.shift_left(100000000), limited)?
}

test "power radix parsing keeps digit order leading zeros and strict budgets" {
	expect_equal((parse_big_int("-000101", 2)?).to_int(), -5)?
	expect_equal((parse_big_int("+000123", 4)?).to_int(), 27)?
	expect_equal((parse_big_int("-000777", 8)?).to_int(), -511)?
	expect_equal((parse_big_int("+000Ff", 16, 5)?).to_int(), 255)?
	expect_equal((parse_big_int("-000Vv", 32)?).to_int(), -1023)?
	expect_equal((parse_big_int("-000", 32)?).sign(), 0)?

	limited BigInt! := error(Error("big integer: limit exceeded", kind: "EOVERFLOW"))
	malformed BigInt! := error(Error("big integer: invalid data", kind: "EBADMSG"))
	expect_equal(parse_big_int("+000Ff", 16, 4), limited)?
	expect_equal(parse_big_int("+0_1", 16, 2), limited)?
	expect_equal(parse_big_int("+0_1", 16, 3), malformed)?
}
