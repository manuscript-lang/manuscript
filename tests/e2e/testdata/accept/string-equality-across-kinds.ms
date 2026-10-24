from "@std/testing.ms" import expect_equal

def same(a: String, b: String) -> Bool:
    return a == b

def built(parts: List[String]) -> String:
    var s = ""
    for p in parts:
        s = s + p
    return s

test "equal text is equal whether stored inline, static, owned, or borrowed":
    let short = built(["ab", "cd"])
    try expect_equal(same(short, "abcd"), True)
    try expect_equal(same("abcd", short), True)
    try expect_equal(same(short, built(["a", "bcd"])), True)

    let long = built(["a long string ", "past fifteen bytes"])
    try expect_equal(same(long, "a long string past fifteen bytes"), True)
    try expect_equal(same(long, built(["a long string past ", "fifteen bytes"])), True)
    try expect_equal(same("  abcd ".trim(), short), True)

    let pieces = "abcd,a long string past fifteen bytes".split(",")
    try expect_equal(same(pieces.get(0), short), True)
    try expect_equal(same(pieces.get(1), long), True)
    try expect_equal(same(built(["", ""]), ""), True)

test "different text is different at every length and kind":
    let short = built(["ab", "cd"])
    try expect_equal(same(short, "abce"), False)
    try expect_equal(same(short, "abc"), False)
    try expect_equal(same(short, built(["abcd", "e"])), False)
    try expect_equal(
        same(built(["fifteen ", "bytes!!"]), built(["fifteen ", "bytes!?"])), False
    )
    try expect_equal(
        same(built(["fifteen ", "bytes!!"]), built(["fifteen ", "bytes!!!"])), False
    )

    let long = built(["a long string ", "past fifteen bytes"])
    try expect_equal(same(long, built(["a long string ", "past fifteen bytez"])), False)
    try expect_equal(same(long, short), False)
    try expect_equal(same(built([f"ab\u{0}", "c"]), "ab"), False)
