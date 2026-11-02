# conform: tags=stdlib-math,testing
# conform: phase=test
import expect_equal from "@std/test/test.ms"

test "UInt64 to_string agrees with interpolation above Int max":
    let v = 4294967295.to_uint64().get(0) * 4294967296 + 4294967295
    try expect_equal(v.to_string(), "18446744073709551615")
    try expect_equal(v.to_string(), "{v}")
    try expect_equal(v.to_string(), v.to_string_radix(10))
