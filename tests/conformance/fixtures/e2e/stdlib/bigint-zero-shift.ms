// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	BigInt, from_int from "@std/math/math.ms",
	expect_equal, expect_fault from "@std/test/test.ms",
)

test "zero shifts have zero result bits at every nonnegative count":
	for count in [0, 16777216, 16777217, 9223372036854775807]:
		expect_equal((from_int(0).shift_left(count)?).to_int(), 0)?

	_negative := expect_fault(fn: discard(from_int(0).shift_left(-1)))?

test "nonzero shifts still enforce the result bit budget":
	limit := 16777216
	limited: BigInt! := error(Error("big integer: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(from_int(1).shift_left(limit), limited)?
	expect_equal(from_int(-1).shift_left(limit), limited)?

	largest_power := from_int(1).shift_left(limit - 1)?
	expect_equal((largest_power.shift_right(limit - 1)).to_int(), 1)?

fn discard[T](value: T) Void:
	return
