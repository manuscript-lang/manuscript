// conform: tags=testing,numbers,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn byte_sum(values: List[UInt8]) Int:
	var total = 0
	var i = 0

	while i < values.length():
		total += values.get(i).to_int()
		i += 1

	return total

fn signed_sum(values: List[Int8]) Int:
	var total = 0
	var i = 0

	while i < values.length():
		total += values.get(i).to_int()
		i += 1

	return total

test "a sum of bytes is the exact total":
	var values = List[UInt8]()
	var i = 0

	while i < 1000:
		values.append((i % 256).to_uint8().get())
		i += 1

	expect_equal(byte_sum(values), 124716)?

test "a sum of signed bytes goes negative without a fault":
	var values = List[Int8]()
	var i = 0

	while i < 300:
		values.append((-100).to_int8().get())
		i += 1

	expect_equal(signed_sum(values), -30000)?
