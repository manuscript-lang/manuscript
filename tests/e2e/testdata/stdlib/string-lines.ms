import expect_equal from "@std/test.ms"

test "lines preserve boundaries across search windows and unaligned starts":
    for width in [0, 1, 7, 8, 15, 16, 31, 32, 63, 64, 1024]:
        let prefix = "x".repeat(width).get()
        let text = prefix + "\n\r\né日😀\r\n\nlast\r"
        try expect_equal(text.lines(), [prefix, "", "é日😀", "", "last\r"])
        try expect_equal((prefix + "\n").lines(), [prefix])
        try expect_equal((prefix + "\r\n").lines(), [prefix])

test "lines leave embedded NUL and non LF separators unchanged":
    let text = "a\u{0}b\r漢\u{85}\u{2028}\u{2029}😀"
    try expect_equal(text.lines(), [text])
    try expect_equal("".lines(), [])
    try expect_equal("\n\n".lines(), ["", ""])
