import expect_equal from "@std/test/test.ms"
import parse_float from "@std/math/math.ms"

test "precision formatting preserves signed zero significant padding and special values":
    try expect_equal((-0.0).to_precision(1), "-0")
    try expect_equal((-0.0).to_precision(4), "-0.000")
    try expect_equal(0.0.to_precision(4), "0.000")
    try expect_equal(1.0.to_precision(4), "1.000")
    try expect_equal(9.5.to_precision(1), "1e+1")
    try expect_equal(9.5.to_precision(2), "9.5")
    try expect_equal(0.000001.to_precision(3), "0.00000100")
    try expect_equal(0.0000001.to_precision(3), "1.00e-7")
    try expect_equal((try parse_float("NaN")).to_precision(3), "NaN")
    try expect_equal((try parse_float("Infinity")).to_precision(3), "Infinity")
    try expect_equal((try parse_float("-Infinity")).to_precision(3), "-Infinity")
