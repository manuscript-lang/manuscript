// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

extern fn abs(value: Int32) Int32

extern fn toupper(value: Int32) Int32

extern fn htons(value: UInt16) UInt16

extern fn sqrtf(value: Float32) Float32

test "sized integers cross a C call as their own width":
	expect_equal(abs(-5), 5)?
	expect_equal(toupper(97), 65)?
	expect_equal(toupper(-1), -1)?
	expect_equal(htons(258), 513)?

test "a Float32 crosses a C call as a float":
	expect_equal(sqrtf(2.25).to_float(), 1.5)?
