// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	constant_time_less_or_equal,
	constant_time_select,
	xor_bytes from "@std/crypto/crypto.ms",
	expect_equal, expect_fault, expect_true from "@std/test/test.ms",
)

test "constant time select picks by choice":
	expect_equal(constant_time_select(1, 7, 9), 7)?
	expect_equal(constant_time_select(0, 7, 9), 9)?

test "constant time less-or-equal orders non-negative values":
	expect_equal(constant_time_less_or_equal(3, 4), 1)?
	expect_equal(constant_time_less_or_equal(4, 4), 1)?
	expect_equal(constant_time_less_or_equal(5, 4), 0)?
	expect_equal(constant_time_less_or_equal(0, 0), 1)?

test "xor_bytes combines equal lengths and faults on others":
	mixed := xor_bytes(Bytes([1, 2, 255]), Bytes([3, 2, 15]))
	expect_equal(mixed.get(0).to_int(), 2)?
	expect_equal(mixed.get(1).to_int(), 0)?
	expect_equal(mixed.get(2).to_int(), 240)?

	_lengths := expect_fault(fn: discard(xor_bytes(Bytes([1]), Bytes([]))))?

fn discard[T](value: T) Void:
	return
