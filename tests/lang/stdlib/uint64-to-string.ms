// conform: tags=stdlib-math,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "UInt64 to_string agrees with interpolation above Int max" {
	v := (4294967295.to_uint64() or 0) * 4294967296 + 4294967295
	expect_equal(v.to_string(), "18446744073709551615")?
	expect_equal(v.to_string(), f"{v}")?
	expect_equal(v.to_string(), v.to_string())?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
