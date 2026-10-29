import expect_equal from "@std/test.ms"
import {min_int, max_int} from "@std/math.ms"

# Integer interpolations are written straight into the joined text (the `strfuse` pass passes the
# integer to `msrt_string_fmtN`), so every integer shape and length must still read back the same.
fn label(prefix: String, n: Int) String:
    return "{prefix}{n}"

fn pair(a: Int, sep: String, b: Int) String:
    return "{a}{sep}{b}"

test "integer interpolation shapes":
    try expect_equal(label("w", 1234), "w1234")
    try expect_equal(label("", 0), "0")
    try expect_equal(label("n=", -7), "n=-7")
    try expect_equal(pair(1, ":", 2), "1:2")
    try expect_equal(pair(-1, "", -2), "-1-2")
    try expect_equal("{min_int()}", "-9223372036854775808")
    try expect_equal(
        "{max_int()}|{min_int()}", "9223372036854775807|-9223372036854775808"
    )

test "integer interpolation at the inline boundary":
    # 14 bytes of text plus one digit is the longest inline string; one more byte allocates.
    try expect_equal("abcdefghijklmn{5}", "abcdefghijklmn5")
    try expect_equal("abcdefghijklmn{56}", "abcdefghijklmn56")
    try expect_equal("abcdefghijklmn{56}".length(), 16)

test "integer interpolation in loops and chains":
    var parts = List[String]()
    for i in 0..5:
        parts.append("{i}-{i * i}-{i + 1}")
    try expect_equal(parts.join(","), "0-0-1,1-1-2,2-4-3,3-9-4,4-16-5")

    let n = 42
    let s = "x"
    try expect_equal("{n}{s}{n}{s}{n}{s}", "42x42x42x")
    try expect_equal("{n}{n}{n}{n}{n}{n}{n}", "42424242424242")

    let t = "{n}"
    try expect_equal("{t}{n}", "4242")
