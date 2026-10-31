import expect_equal from "@std/test.ms"

type ReverseExample:
    original: String
    reversed: String

test "reversal keeps scalar order across UTF-8 widths and combining sequences":
    for item in [
        ReverseExample("", ""),
        ReverseExample("a", "a"),
        ReverseExample("éΩüß", "ßüΩé"),
        ReverseExample("日漢€☃", "☃€漢日"),
        ReverseExample("😀🙂🚀🌍", "🌍🚀🙂😀"),
        ReverseExample(
            "aé日😀\u{0}e\u{301}\u{fffd}", "\u{fffd}\u{301}e\u{0}😀日éa"
        ),
        ReverseExample("👩\u{200d}🚀", "🚀\u{200d}👩")
    ]:
        try expect_equal(item.original.reverse(), item.reversed)
        try expect_equal(item.reversed.reverse(), item.original)

test "reversal handles byte boundaries with Unicode at either end":
    for size in [0, 1, 2, 7, 8, 15, 16, 17, 31, 32, 63, 64, 127, 128, 4096]:
        let prefix = "x".repeat(size).get()
        try expect_equal((prefix + "é日😀").reverse(), "😀日é" + prefix)
        try expect_equal(("é日😀" + prefix).reverse(), prefix + "😀日é")
        try expect_equal(
            (prefix + "\u{0}\t\n\u{7f}").reverse(), "\u{7f}\n\t\u{0}" + prefix
        )
