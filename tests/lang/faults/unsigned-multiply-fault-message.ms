// conform: tags=faults,numbers,testing,tier-stdlib
// conform: phase=test
import expect_contains, expect_fault from "@std/test/test.ms"

fn times(a UInt32, b UInt32) UInt32 {
	return a * b
}

// The product of two UInt32 values can pass 63 bits before the type's range check, so
// the message must still name the sized type on every backend.
test "a UInt32 product above 63 bits names the sized range" {
	message := expect_fault(
		() => {
			_bad := times(a: 3041828323, b: 3041828323)
		}
	)?
	message | expect_contains("sized integer type's range")?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
