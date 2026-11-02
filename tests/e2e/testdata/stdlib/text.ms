import expect_equal, expect_error, expect_ok from "@std/test/test.ms"
import StringError, from_scalars from "@std/string.ms"
import (parse_bool, parse_int_radix, quote, quote_ascii, unquote) from "@std/text.ms"

test "text conversions and quoting":
    parse_bool("YES") | try expect_equal(true)
    parse_bool("x") | try expect_equal(none)
    parse_int_radix("-ff", 16) | try expect_equal(-255)
    parse_int_radix("0b101", 0) | try expect_equal(5)
    parse_int_radix("9223372036854775807", 10) | try expect_equal(9223372036854775807)
    parse_int_radix("-9223372036854775808", 10) | try expect_equal(
        -9223372036854775807 - 1
    )
    parse_int_radix("9223372036854775808", 10) | try expect_equal(none)
    parse_int_radix("12", 2) | try expect_equal(none)
    quote("a\"b\n") | try expect_equal("\"a\\\"b\\n\"")
    quote_ascii("é🙂") | try expect_equal("\"\\u\{e9\}\\u\{1f642\}\"")
    unquote("\"a\\tb\\u\{e9\}\"") | try expect_ok | try expect_equal("a\tbé")
    unquote("abc") | try expect_error | try expect_equal(StringError.InvalidInput)
    unquote("\"a\"b\"") | try expect_error | try expect_equal(StringError.InvalidInput)
    unquote("\"\\q\"") | try expect_error | try expect_equal(StringError.InvalidInput)
    unquote("\"\\u\{d800\}\"") | try expect_error | try expect_equal(
        StringError.InvalidInput
    )
    unquote(quote("tab\there \"q\" \\ é🙂\u{1}")) | try expect_ok | try expect_equal(
        "tab\there \"q\" \\ é🙂\u{1}"
    )

test "text quoting escapes interpolation braces and literal controls":
    quote("\{x\}") | try expect_equal("\"\\\{x\\\}\"")
    unquote("\"\\\{x\\\}\"") | try expect_ok | try expect_equal("\{x\}")
    quote("\}") | try expect_equal("\"\\\}\"")
    unquote("\"\\\}\"") | try expect_ok | try expect_equal("\}")
    quote("\\u\{41\}") | try expect_equal("\"\\\\u\\\{41\\\}\"")
    unquote("\"\\\\u\\\{41\\\}\"") | try expect_ok | try expect_equal("\\u\{41\}")

    for scalar in [0, 31, 127, 128, 133, 159, 8232, 8233, 8234, 8238, 8294, 8297]:
        let text = try from_scalars([scalar])
        let expected = "\"\\u\{" + scalar.to_string_radix(16) + "\}\""
        quote(text) | try expect_equal(expected)
        unquote(quote(text)) | try expect_ok | try expect_equal(text)

test "text Unicode escapes reject signs nonhex digits and excess width":
    for text in [
        "\"\\u\{\}\"", "\"\\u\{+41\}\"", "\"\\u\{-0\}\"", "\"\\u\{ 41\}\"",
        "\"\\u\{41 \}\"", "\"\\u\{0x41\}\"", "\"\\u\{0000000\}\"",
        "\"\\u\{00000041\}\"", "\"\\u\{g\}\"", "\"\\u\{d800\}\"", "\"\\u\{110000\}\"",
        "\"\\u\{ffffffffffffffff\}\""
    ]:
        unquote(text) | try expect_error | try expect_equal(StringError.InvalidInput)

test "text Unicode escapes preserve scalar boundaries and leading zeros":
    unquote("\"\\u\{000000\}\"") | try expect_ok | try expect_equal(
        try from_scalars([0])
    )
    unquote("\"\\u\{000041\}\"") | try expect_ok | try expect_equal(
        try from_scalars([65])
    )
    unquote("\"\\u\{d7ff\}\"") | try expect_ok | try expect_equal(
        try from_scalars([55295])
    )
    unquote("\"\\u\{E000\}\"") | try expect_ok | try expect_equal(
        try from_scalars([57344])
    )
    unquote("\"\\u\{10FFFF\}\"") | try expect_ok | try expect_equal(
        try from_scalars([1114111])
    )

test "text quoting round trips scalar and escape neighbors":
    for scalar in [
        0, 9, 10, 13, 31, 32, 34, 92, 123, 125, 127, 128, 159, 233, 2047, 2048, 8234,
        8297, 55295, 57344, 65535, 65536, 1114111
    ]:
        let text = "prefix " + (try from_scalars([scalar])) + " suffix"
        unquote(quote(text)) | try expect_ok | try expect_equal(text)

        let ascii = quote_ascii(text)
        for value in ascii.scalar_values():
            (value < 128) | try expect_equal(true)
        unquote(ascii) | try expect_ok | try expect_equal(text)
