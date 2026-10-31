import expect_equal, expect_true from "@std/test.ms"
import infinity, parse_float from "@std/math.ms"

test "parse_float reads integers decimals and exponents":
    "42".parse_float() | try expect_equal(42.0)
    "-0.5".parse_float() | try expect_equal(-0.5)
    "+3.25".parse_float() | try expect_equal(3.25)
    "-1.25e2".parse_float() | try expect_equal(-125.0)
    "5E-1".parse_float() | try expect_equal(0.5)

test "parse_float accepts the special spellings of math.parse_float":
    "Infinity".parse_float() | try expect_equal(infinity())
    "-Infinity".parse_float() | try expect_equal(-infinity())
    try expect_true("NaN".parse_float().get().is_nan())

test "parse_float returns none for invalid or out-of-range text":
    for text in [
        "", " 1.0", "1.0 ", "1_0", "1.", ".5", "0x1p2", "nan", "inf", "abc", "1e999"
    ]:
        text.parse_float() | try expect_equal(none)

test "parse_float agrees with math.parse_float":
    for text in ["7", "-2.5e3", "1.", "oops", "1e999"]:
        text.parse_float() | try expect_equal(parse_float(text).to_optional())
