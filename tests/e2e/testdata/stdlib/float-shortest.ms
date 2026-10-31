import expect_equal from "@std/test.ms"
import infinity, nan from "@std/math.ms"

test "Float shortest strings keep notation boundaries and special values":
    try expect_equal((1.0 / 3.0).to_string(), "0.3333333333333333")
    try expect_equal(1e-6.to_string(), "0.000001")
    try expect_equal(1e-7.to_string(), "1e-7")
    try expect_equal(1e20.to_string(), "100000000000000000000")
    try expect_equal(1e21.to_string(), "1e+21")
    try expect_equal((-0.0).to_string(), "-0")
    try expect_equal(infinity.to_string(), "Infinity")
    try expect_equal((-infinity).to_string(), "-Infinity")
    try expect_equal(nan.to_string(), "NaN")
