import expect_equal from "@std/test.ms"
import parse_int, parse_float, NumberError from "@std/math.ms"

test "numbers radix and signed boundaries":
    try expect_equal((try parse_int("7fffffffffffffff", 16)), 9223372036854775807)
    try expect_equal((try parse_int("-9223372036854775808", 10)), -9223372036854775808)
    try expect_equal(255.to_string_radix(16), "ff")
    try expect_equal((try parse_float("-1.25e2")), -125.0)
    try expect_equal(1.25.to_fixed(2), "1.25")
    try expect_equal(1.9.truncate_to_int(), 1)

test "numbers reject whitespace separators overflow and invalid radix":
    let invalid: Int!NumberError = error(NumberError.InvalidData)
    for text in [" 1", "1_0", "0x10", "+", "١"]:
        try expect_equal(parse_int(text, 10), invalid)

    let overflow: Int!NumberError = error(NumberError.OutOfRange)
    try expect_equal(parse_int("9223372036854775808", 10), overflow)

    let radix_error: Int!NumberError = error(NumberError.InvalidInput)
    try expect_equal(parse_int("1", 1), radix_error)

    let float_error: Float!NumberError = error(NumberError.InvalidData)
    for text in [" 1.0", "1_0", "1.", "0x1p2"]:
        try expect_equal(parse_float(text), float_error)
