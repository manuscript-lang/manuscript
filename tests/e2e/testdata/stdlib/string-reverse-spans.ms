import expect_equal from "@std/test.ms"

type ReverseCase:
    text: String
    expected: String

test "reverse preserves scalar order, literal replacement characters and controls":
    let cases = [
        ReverseCase("", ""), ReverseCase("x", "x"), ReverseCase("\u{fffd}", "\u{fffd}"),
        ReverseCase("a\u{0}z", "z\u{0}a"), ReverseCase("aé日😀", "😀日éa"),
        ReverseCase("e\u{301}", "\u{301}e"), ReverseCase("👩\u{200d}🚀", "🚀\u{200d}👩"),
        ReverseCase("a\u{fffd}é日😀\u{0}", "\u{0}😀日é\u{fffd}a")
    ]

    for reverse_case in cases:
        try expect_equal(reverse_case.text.reverse(), reverse_case.expected.clone())
        try expect_equal(
            reverse_case.text.reverse().reverse(), reverse_case.text.clone()
        )

test "reverse keeps mixed width spans correct around byte boundaries and large prefixes":
    for length in [0, 1, 2, 7, 8, 15, 16, 17, 31, 32, 63, 64, 128, 4096, 1048576]:
        let prefix = "x".repeat(length).get()
        let text = prefix + "é日😀\u{0}\u{fffd}"
        let expected = "\u{fffd}\u{0}😀日é" + prefix
        try expect_equal(text.reverse(), expected)
        try expect_equal(text.reverse().reverse(), text)
