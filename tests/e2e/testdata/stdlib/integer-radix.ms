import expect_equal from "@std/test/test.ms"

test "integer radix formatting keeps signs zero and high unsigned bits":
	expect_equal(0.to_string_radix(2), "0")?
	expect_equal(255.to_string_radix(4), "3333")?
	expect_equal(255.to_string_radix(8), "377")?
	expect_equal((-255).to_string_radix(16), "-ff")?
	expect_equal(255.to_string_radix(32), "7v")?
	expect_equal((-9223372036854775808).to_string_radix(16), "-8000000000000000")?

	maximum: UInt64 := 18446744073709551615
	expect_equal(
		maximum.to_string_radix(2),
		"1111111111111111111111111111111111111111111111111111111111111111",
	)?
	expect_equal(maximum.to_string_radix(16), "ffffffffffffffff")?
	expect_equal(maximum.to_string_radix(36), "3w5e11264sgsf")?
	expect_equal(9223372036854775807.to_string_radix(10), "9223372036854775807")?
	expect_equal((-9223372036854775808).to_string_radix(10), "-9223372036854775808")?
	expect_equal(maximum.to_string_radix(10), "18446744073709551615")?

	unsigned_zero: UInt64 := 0
	expect_equal(unsigned_zero.to_string_radix(10), "0")?
