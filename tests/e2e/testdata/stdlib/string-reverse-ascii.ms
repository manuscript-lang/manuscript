import expect_equal from "@std/test.ms"

test "ASCII reversal preserves control bytes and Unicode fallback at either end":
    try expect_equal("".reverse(), "")
    try expect_equal("x".reverse(), "x")
    try expect_equal("\u{0}".reverse(), "\u{0}")
    try expect_equal("\u{7f}".reverse(), "\u{7f}")
    try expect_equal("a\u{0}b\tc\nd!".reverse(), "!d\nc\tb\u{0}a")

    let ascii = "x".repeat(1048576).get()
    try expect_equal((ascii + "é日😀").reverse(), "😀日é" + ascii)
    try expect_equal(("é日😀" + ascii).reverse(), ascii + "😀日é")
