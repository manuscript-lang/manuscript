import (
	infinity, nan from "@std/math/math.ms",
	expect_equal from "@std/test/test.ms",
)

test "Float shortest strings keep notation boundaries and special values":
	expect_equal((1.0 / 3.0).to_string(), "0.3333333333333333")?
	expect_equal(1e-6.to_string(), "0.000001")?
	expect_equal(1e-7.to_string(), "1e-7")?
	expect_equal(1e20.to_string(), "100000000000000000000")?
	expect_equal(1e21.to_string(), "1e+21")?
	expect_equal((-0.0).to_string(), "-0")?
	expect_equal(infinity.to_string(), "Infinity")?
	expect_equal((-infinity).to_string(), "-Infinity")?
	expect_equal(nan.to_string(), "NaN")?
