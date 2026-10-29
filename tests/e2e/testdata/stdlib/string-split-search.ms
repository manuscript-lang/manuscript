import expect_equal from "@std/test.ms"

test "materialized splitting preserves exact separators and truncated caps":
    let empty: List[String] = []
    try expect_equal("".split("::"), [""])
    try expect_equal("::a::::".split("::"), ["", "a", "", ""])
    try expect_equal("::a::::".split("::", none), ["", "a", "", ""])
    try expect_equal("::a::::".split("::", 0), empty)
    try expect_equal("a::b::c".split("::", 1), ["a"])
    try expect_equal("a::b::c".split("::", 2), ["a", "b"])
    try expect_equal("a::b::c".split("::", 9), ["a", "b", "c"])
    try expect_equal("aaaaa".split("aa"), ["", "", "a"])
    try expect_equal("a".split("longer"), ["a"])
    try expect_equal("é日😀日終日".split("日"), ["é", "😀", "終", ""])
    try expect_equal("é日😀".split("", 2), ["é", "日"])

test "materialized splitting crosses both search thresholds":
    for width in [0, 1, 24, 25, 55, 56, 57, 58, 88]:
        let prefix = try "x".repeat(width)
        let text = prefix + "::a::::"
        try expect_equal(text.split("::"), [prefix.clone(), "a", "", ""])
        try expect_equal(text.split("::", 1), [prefix.clone()])
        try expect_equal(text.split("::", 2), [prefix, "a"])
        try expect_equal(text.split("missing"), [text])

    let prefix = try "x".repeat(64)
    try expect_equal((prefix + ":a::").split(":"), [prefix.clone(), "a", "", ""])

test "materialized splitting reuses multi-byte separators through short tails":
    let long_separator = try "abcdefghij".repeat(9)

    for separator in ["::", "<split>", long_separator]:
        for count in [2, 8, 64]:
            let text = (try ("é" + separator).repeat(count)) + "終"
            let parts = text.split(separator)
            try expect_equal(parts.length(), count + 1)

            var index = 0

            for part in parts:
                if index < count:
                    try expect_equal(part, "é")
                else:
                    try expect_equal(part, "終")

                index += 1

            try expect_equal(text.split(separator, 1), ["é"])
            try expect_equal(text.split(separator, 2), ["é", "é"])

            let terminated = try ("é" + separator).repeat(count)
            let trailing = terminated.split(separator)
            try expect_equal(trailing.length(), count + 1)
            try expect_equal(trailing.get(-1), "")

test "two separators preserve a long absent tail and exact caps":
    let long_separator = try "abcdefghij".repeat(9)

    for separator in ["::", "<split>", long_separator]:
        for width in [63, 64, 65, 256]:
            let tail = try "z".repeat(width)
            let text = "a" + separator + "b" + separator + tail
            try expect_equal(text.split(separator), ["a", "b", tail.clone()])
            try expect_equal(text.split(separator, 2), ["a", "b"])
            try expect_equal(text.split(separator, 3), ["a", "b", tail])
