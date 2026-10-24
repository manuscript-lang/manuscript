import {expect_equal} from "@std/testing.ms"

fn same(a: String, b: String) Bool:
    return a == b

fn built(parts: List[String]) String:
    var s = ""
    for p in parts:
        s = s + p
    return s

test "equal text is equal whether stored inline, static, owned, or borrowed":
    let short = built(["ab", "cd"])
    try expect_equal(same(short, "abcd"), true)
    try expect_equal(same("abcd", short), true)
    try expect_equal(same(short, built(["a", "bcd"])), true)

    let long = built(["a long string ", "past fifteen bytes"])
    try expect_equal(same(long, "a long string past fifteen bytes"), true)
    try expect_equal(same(long, built(["a long string past ", "fifteen bytes"])), true)
    try expect_equal(same("  abcd ".trim(), short), true)

    let pieces = "abcd,a long string past fifteen bytes".split(",")
    try expect_equal(same(pieces.get(0), short), true)
    try expect_equal(same(pieces.get(1), long), true)
    try expect_equal(same(built(["", ""]), ""), true)

test "different text is different at every length and kind":
    let short = built(["ab", "cd"])
    try expect_equal(same(short, "abce"), false)
    try expect_equal(same(short, "abc"), false)
    try expect_equal(same(short, built(["abcd", "e"])), false)
    try expect_equal(
        same(built(["fifteen ", "bytes!!"]), built(["fifteen ", "bytes!?"])), false
    )
    try expect_equal(
        same(built(["fifteen ", "bytes!!"]), built(["fifteen ", "bytes!!!"])), false
    )

    let long = built(["a long string ", "past fifteen bytes"])
    try expect_equal(same(long, built(["a long string ", "past fifteen bytez"])), false)
    try expect_equal(same(long, short), false)
    try expect_equal(same(built(["ab\u{0}", "c"]), "ab"), false)
