import expect_contains, expect_equal, expect_fault, expect_true from "@std/test/test.ms"

fn signed() Int8: + (100 + 27)

fn unsigned() UInt8: + 255

fn minimum() Int8: + (-128)

fn negative() Int8: -(+ 127)

fn rounded() Float32: + 1.0000000596046448

fn add(value: Int8) Int8: value + + 1

test "unary signs preserve sized literal context":
	try expect_equal(signed().to_int(), 127)
	try expect_equal(unsigned().to_int(), 255)
	try expect_equal(minimum().to_int(), -128)
	try expect_equal(negative().to_int(), -127)
	try expect_equal(add(1).to_int(), 2)
	try expect_equal(rounded().to_float64(), 1.0000001192092896)

	values: List[Int8] = [+ 1, + 2]
	try expect_true(values == [+ 1, + 2])

fn negative_minimum() Int8: -(-128)

fn negative_signed_minimum() Int8: -(+ (-128))

test "nested sign overflow still faults":
	(try expect_fault(fn: _ignored := negative_minimum())) | try expect_contains(
		"overflow"
	)
	(try expect_fault(fn: _ignored := negative_signed_minimum())) | try expect_contains(
		"overflow"
	)
