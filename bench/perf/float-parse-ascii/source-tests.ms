import expect_equal from "@std/test.ms"
import parse_float, NumberError from "@std/math.ms"

test "float parsing keeps ASCII signs decimals and exponents":
    for text in ["1.25", "+1.25", "125e-2", "0.125E+1"]:
        try expect_equal(text.parse_float().get(), 1.25)
        try expect_equal((try parse_float(text)), 1.25)

    try expect_equal("-0".parse_float().get().to_string(), "-0")
    try expect_equal((try parse_float("-0")).to_string(), "-0")

test "float parsing rejects Unicode syntax and malformed or overflowing text":
    let invalid: Float!NumberError = error(NumberError.InvalidData)

    for text in ["١", "１", "1.٢", "1e٣", "−1", "1 ", ".5", "1.", "1e+", " 1", "1_0"]:
        try expect_equal(text.parse_float(), none)
        try expect_equal(parse_float(text), invalid)

    try expect_equal("1e400".parse_float(), none)

    let overflow: Float!NumberError = error(NumberError.OutOfRange)
    try expect_equal(parse_float("1e400"), overflow)

    let huge = "9".repeat(4096).get()
    try expect_equal(huge.parse_float(), none)
    try expect_equal(parse_float(huge), overflow)
    try expect_equal(parse_float("{huge}!"), invalid)
