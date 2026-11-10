import expect_equal, expect_true from "@std/test/test.ms"

fn negative() Int8: -0x7d

fn add_small(value: Int8) Int8: value + 0x1d

fn add_expression(value: Int8) Int8: value + (0x1e - 0x1d)

test "hex digits retain integer kind in sized contexts":
	try expect_equal(negative().to_int(), -125)
	try expect_equal(add_small(1).to_int(), 30)
	try expect_equal(add_expression(1).to_int(), 2)

	values: List[Int8] = [0x1d, 0x1e]
	try expect_true(values == [0x1d, 0x1e])
