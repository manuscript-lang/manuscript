import expect_equal from "@std/test.ms"

test "empty boundary replacements preserve text at result size boundaries":
    for pattern in ["x", "é日😀", "a\u{0}b"]:
        for count in [0, 1, 7, 8, 15, 16, 17, 31, 32, 4096]:
            let text = pattern.repeat(count).get()
            try expect_equal(text.replace("", ""), text)
            try expect_equal(text, pattern.repeat(count).get())

test "empty replacement fast path leaves insertion and ordinary matching intact":
    try expect_equal("".replace("", ""), "")
    try expect_equal("é日😀".replace("", "-"), "-é-日-😀-")
    try expect_equal("a\u{0}b".replace("", "-"), "-a-\u{0}-b-")
    try expect_equal("é日😀".replace("日", "日日"), "é日日😀")
    try expect_equal("é日😀".replace("日", ""), "é😀")
    try expect_equal("abc".replace("|", "!"), "abc")
