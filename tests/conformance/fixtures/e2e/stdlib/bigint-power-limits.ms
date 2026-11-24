// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	BigInt, big_int_of_int from "@std/math/math.ms",
	expect_equal from "@std/test/test.ms",
)

test "big integer powers enforce the exact result bit limit":
	limit := 16777216
	limited BigInt! := error(Error("big integer: limit exceeded", kind: "EOVERFLOW"))
	largest_power := big_int_of_int(2).pow(limit - 1)?
	expect_equal((largest_power.shift_right(limit - 1)?).to_int(), 1)?
	expect_equal(big_int_of_int(2).pow(limit), limited)?
	expect_equal(big_int_of_int(-2).pow(limit), limited)?

	oversized := largest_power.multiply(big_int_of_int(2))
	expect_equal(oversized.pow(1), limited)?
	expect_equal((oversized.pow(0)?).to_int(), 1)?

	power := big_int_of_int(1).shift_left(limit / 3 + 1)?
	dense := power.subtract(big_int_of_int(1))
	expect_equal(dense.pow(3), limited)?
	expect_equal(dense.negate().pow(3), limited)?

test "constant big integer powers remain valid at huge exponents":
	maximum := 9223372036854775807
	expect_equal((big_int_of_int(0).pow(maximum)?).to_int(), 0)?
	expect_equal((big_int_of_int(1).pow(maximum)?).to_int(), 1)?
	expect_equal((big_int_of_int(-1).pow(maximum)?).to_int(), -1)?
	expect_equal((big_int_of_int(-1).pow(maximum - 1)?).to_int(), 1)?
	expect_equal((big_int_of_int(0).pow(0)?).to_int(), 1)?
