import expect_equal from "@std/test/test.ms"
import parse_int from "@std/math/math.ms"

test "integer radix parsing preserves signed boundaries in every base":
    for radix in 2..37:
        for value in [
            -9223372036854775808, -9223372036854775807, -1, 0, 1, 9223372036854775807
        ]:
            try expect_equal(
                (try parse_int(value.to_string_radix(radix), radix)), value
            )
        try expect_equal((try parse_int("+0001", radix)), 1)
        try expect_equal((try parse_int("-0000", radix)), 0)

test "integer radix syntax errors take precedence after overflow":
    let overflow: Int! = error(
        Error("number: value out of range", kind: ErrorCategory.OutOfRange)
    )
    let invalid: Int! = error(
        Error("number: invalid data", kind: ErrorCategory.InvalidData)
    )

    for text in [
        "9223372036854775808", "-9223372036854775809", "18446744073709551616",
        "-18446744073709551616"
    ]:
        try expect_equal(parse_int(text, 10), overflow)
        try expect_equal(parse_int("{text}!", 10), invalid)

    let huge = "9".repeat(4096).get()
    try expect_equal(parse_int(huge, 10), overflow)
    try expect_equal(parse_int("{huge}!", 10), invalid)

    let zeros = "0".repeat(4096).get()
    try expect_equal((try parse_int("{zeros}1", 10)), 1)
