import {expect_equal, expect_false, fail} from "@std/testing.ms"

test "String basic counterparts are callable":
    try expect_equal("é🙂".length(), 2)
    try expect_false(not ("".is_empty()) or "a".is_empty())
    try expect_equal("é🙂".chars(), ["é", "🙂"])
    try expect_equal("é🙂".reverse(), "🙂é")
    try expect_false(
        (
            "a".compare("b") != -1
            or "b".compare("a") != 1
            or "é".compare("é") != 0
        )
    )
    try expect_equal("a\r\nb\n".lines(), ["a", "b"])

test "length and chars use scalars and preserve text boundaries":
    let text = "é🙂e\u{301}"
    try expect_false(text.length() != 4 or text.length() != text.scalar_length())
    try expect_equal(text.chars(), ["é", "🙂", "e", "\u{301}"])
    try expect_equal("👩\u{200d}🚀".length(), 3)
    try expect_equal("a\u{0}b".chars(), ["a", "\u{0}", "b"])
    try expect_false(not ("".chars().is_empty()) or "".length() != 0)
    let characters = text.chars()
    let second = text.chars()
    characters.set(0, "changed").append("new")
    try expect_false(second != ["é", "🙂", "e", "\u{301}"] or text != "é🙂e\u{301}")

test "reverse operates on scalars without normalization":
    try expect_equal("aé🙂z".reverse(), "z🙂éa")
    try expect_equal("e\u{301}".reverse(), "\u{301}e")
    try expect_equal("👩\u{200d}🚀".reverse(), "🚀\u{200d}👩")
    try expect_equal("a\u{0}b".reverse(), "b\u{0}a")
    try expect_false("".reverse() != "" or "🙂".reverse() != "🙂")
    let original = "é🙂e\u{301}"
    try expect_equal(original.reverse().reverse(), original)

test "compare is normalized sign and scalar lexical order":
    try expect_false("".compare("a") != -1 or "a".compare("") != 1)
    try expect_false("ab".compare("abc") != -1 or "abc".compare("ab") != 1)
    try expect_equal("Z".compare("a"), -1)
    try expect_equal("é".compare("e\u{301}"), 1)
    try expect_equal("\u{e000}".compare("\u{10000}"), -1)
    try expect_equal("a\u{0}".compare("a\u{1}"), -1)
    let equal = "é🙂"
    try expect_equal(equal.compare(equal), 0)

type LineCase:
    text: String
    expected: List[String]

test "lines preserve interior empties and recognize LF and CRLF only":
    let cases = [
        LineCase("", []),
        LineCase("\n", [""]),
        LineCase("\r\n", [""]),
        LineCase("\n\n", ["", ""]),
        LineCase("\r\n\r\n", ["", ""]),
        LineCase("a\n", ["a"]),
        LineCase("a\r\n", ["a"]),
        LineCase("a\n\n", ["a", ""]),
        LineCase("a\r\nb\nc", ["a", "b", "c"]),
        LineCase("a\r", ["a\r"]),
        LineCase("\r", ["\r"]),
        LineCase("\r\r\n", ["\r"]),
        LineCase("a\rb", ["a\rb"]),
        LineCase("é\r\n🙂\n", ["é", "🙂"]),
        LineCase("a\u{0}\nb", ["a\u{0}", "b"]),
        LineCase("a\u{85}b\u{2028}c\u{2029}d", ["a\u{85}b\u{2028}c\u{2029}d"])
    ]
    for line_case in cases:
        if line_case.text.lines() != line_case.expected: return fail(
            "line boundary: {line_case.text.to_string()}"
        )

test "String basic bound methods capture immutable receiver values":
    var text = "é\n🙂\n"
    let chars = text.chars
    let lines = text.lines
    let reverse = text.reverse
    let length = text.length
    let empty = text.is_empty
    let compare = text.compare
    text = "changed"
    try expect_false(chars() != ["é", "\n", "🙂", "\n"] or lines() != ["é", "🙂"])
    try expect_false((reverse() != "\n🙂\né" or length() != 4 or empty()))
    try expect_equal(compare("é\n🙂\n"), 0)
    let first = lines()
    let second = lines()
    first.set(0, "changed").append("new")
    try expect_equal(second, ["é", "🙂"])
    let empty_lines = "".lines()
    empty_lines.append("new")
    try expect_false(not ("".lines().is_empty()))
