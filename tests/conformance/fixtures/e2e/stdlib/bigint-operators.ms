// conform: tags=stdlib-bigint,stdlib-testing,testing,tier-stdlib,numbers
// conform: phase=test
import (
	BigInt, from_int from "@std/math/math.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "big integer operators agree with the named methods":
	a := from_int(-7)
	b := from_int(3)
	expect_equal((a + b).to_int(), -4)?
	expect_equal((a - b).to_int(), -10)?
	expect_equal((a * b).to_int(), -21)?
	expect_equal((a / b).to_int(), -2)?
	expect_equal((a % b).to_int(), -1)?
	expect_equal((-a).to_int(), 7)?
	expect_true(a * b == a.multiply(b))?

test "big integer operators compare exactly":
	a := from_int(2)
	b := from_int(5)
	expect_true(a < b)?
	expect_true(a <= a)?
	expect_true(b > a)?
	expect_true(b >= b)?
	expect_true(a != b)?
	expect_true(a == from_int(2))?

test "big integer operators keep precision past 64 bits":
	var x = from_int(1)
	for i in 0..70:
		x *= from_int(2)
	expect_equal(x.to_int(), none)?
	expect_equal(x.to_string_radix(10), "1180591620717411303424")?
