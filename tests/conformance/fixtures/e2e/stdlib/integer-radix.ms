// conform: tags=testing,tier-stdlib
// conform: phase=test
import big_int_of_int from "@std/math/math.ms"
import expect_equal, expect_none, expect_some from "@std/test/test.ms"

test "integer radix formatting keeps signs zero and high unsigned bits":
	expect_equal(expect_some(0.to_string_radix(2))?, "0")?
	expect_equal(expect_some(255.to_string_radix(4))?, "3333")?
	expect_equal(expect_some(255.to_string_radix(8))?, "377")?
	expect_equal(expect_some((-255).to_string_radix(16))?, "-ff")?
	expect_equal(expect_some(255.to_string_radix(32))?, "7v")?
	expect_equal(expect_some((-9223372036854775808).to_string_radix(16))?, "-8000000000000000")?

	maximum UInt64 := 18446744073709551615
	expect_equal(
		expect_some(maximum.to_string_radix(2))?,
		"1111111111111111111111111111111111111111111111111111111111111111",
	)?
	expect_equal(expect_some(maximum.to_string_radix(16))?, "ffffffffffffffff")?
	expect_equal(expect_some(maximum.to_string_radix(36))?, "3w5e11264sgsf")?
	expect_equal(expect_some(9223372036854775807.to_string_radix(10))?, "9223372036854775807")?
	expect_equal(expect_some((-9223372036854775808).to_string_radix(10))?, "-9223372036854775808")?
	expect_equal(expect_some(maximum.to_string_radix(10))?, "18446744073709551615")?

	unsigned_zero UInt64 := 0
	expect_equal(expect_some(unsigned_zero.to_string_radix(10))?, "0")?

test "radix outside 2 through 36 is none and hex and binary helpers match":
	expect_none(255.to_string_radix(1))?
	expect_none(255.to_string_radix(37))?
	expect_none(255.to_string_radix(-4))?
	expect_none(big_int_of_int(255).to_string_radix(0))?
	expect_none(big_int_of_int(255).to_string_radix(37))?
	maximum UInt64 := 18446744073709551615
	expect_none(maximum.to_string_radix(1))?
	expect_equal((-255).to_hex(), "-ff")?
	expect_equal(5.to_binary(), "101")?
	expect_equal(maximum.to_hex(), "ffffffffffffffff")?
	expect_equal(big_int_of_int(-255).to_hex(), "-ff")?
	expect_equal(big_int_of_int(5).to_binary(), "101")?
