import expect_equal, expect_error, expect_ok from "@std/test/test.ms"
import StringError from "@std/string.ms"
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
