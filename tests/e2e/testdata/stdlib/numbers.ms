import {expect_equal, expect_false, expect_ok} from "@std/testing.ms"
import {parse_int, parse_float, NumberError} from "@std/numbers.ms"

test "numbers radix and signed boundaries":
    parse_int(text: "7fffffffffffffff", radix: 16) | try expect_ok | try expect_equal(
        expected: 9223372036854775807
    )
    try expect_false(
        (
            (
                parse_int(
                    text: "-9223372036854775808",
                    radix: 10
                ) | try expect_ok
            ) != -9223372036854775808
        )
    )
    255.to_string(radix: 16) | try expect_equal(expected: "ff")
    parse_float("-1.25e2") | try expect_ok | try expect_equal(expected: -125.0)
    1.25.to_fixed(digits: 2) | try expect_ok | try expect_equal(expected: "1.25")
    1.9.truncate_to_int() | try expect_equal(expected: some(1))

test "numbers reject whitespace separators overflow and invalid radix":
    let invalid: Result[Int, NumberError] = error(NumberError.InvalidData)
    for text in [" 1", "1_0", "0x10", "+", "١"]:
        parse_int(text: text, radix: 10) | try expect_equal(expected: invalid)
    let overflow: Result[Int, NumberError] = error(NumberError.OutOfRange)
    parse_int(text: "9223372036854775808", radix: 10) | try expect_equal(
        expected: overflow
    )
    let radix_error: Result[Int, NumberError] = error(NumberError.InvalidInput)
    parse_int(text: "1", radix: 1) | try expect_equal(expected: radix_error)
    let float_error: Result[Float, NumberError] = error(NumberError.InvalidData)
    for text in [" 1.0", "1_0", "1.", "0x1p2"]:
        parse_float(text) | try expect_equal(expected: float_error)
