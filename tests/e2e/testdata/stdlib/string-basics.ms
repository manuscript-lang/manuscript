import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"

test "String basic counterparts are callable":
    "é🙂".length() | try expect_equal(expected: 2)
    (not ("".is_empty()) or "a".is_empty()) | try expect_false
    "é🙂".chars() | try expect_equal(expected: ["é", "🙂"])
    "é🙂".reverse() | try expect_equal(expected: "🙂é")
    try expect_false(
        (
            "a".compare("b") != -1
            or "b".compare("a") != 1
            or "é".compare("é") != 0
        )
    )
    "a\r\nb\n".lines() | try expect_equal(expected: ["a", "b"])

test "length and chars use scalars and preserve text boundaries":
    let text = "é🙂e\u{301}"
    (text.length() != 4 or text.length() != text.scalar_length()) | try expect_false
    text.chars() | try expect_equal(expected: ["é", "🙂", "e", "\u{301}"])
    "👩\u{200d}🚀".length() | try expect_equal(expected: 3)
    "a\u{0}b".chars() | try expect_equal(expected: ["a", "\u{0}", "b"])
    (not ("".chars().is_empty()) or "".length() != 0) | try expect_false
    let characters = text.chars()
    let second = text.chars()
    characters.set(0, "changed").append("new")
    (second != ["é", "🙂", "e", "\u{301}"] or text != "é🙂e\u{301}") | try expect_false

test "reverse operates on scalars without normalization":
    "aé🙂z".reverse() | try expect_equal(expected: "z🙂éa")
    "e\u{301}".reverse() | try expect_equal(expected: "\u{301}e")
    "👩\u{200d}🚀".reverse() | try expect_equal(expected: "🚀\u{200d}👩")
    "a\u{0}b".reverse() | try expect_equal(expected: "b\u{0}a")
    ("".reverse() != "" or "🙂".reverse() != "🙂") | try expect_false
    let original = "é🙂e\u{301}"
    original.reverse().reverse() | try expect_equal(expected: original)

test "compare is normalized sign and scalar lexical order":
    ("".compare("a") != -1 or "a".compare("") != 1) | try expect_false
    ("ab".compare("abc") != -1 or "abc".compare("ab") != 1) | try expect_false
    "Z".compare("a") | try expect_equal(expected: -1)
    "é".compare("e\u{301}") | try expect_equal(expected: 1)
    "\u{e000}".compare("\u{10000}") | try expect_equal(expected: -1)
    "a\u{0}".compare("a\u{1}") | try expect_equal(expected: -1)
    let equal = "é🙂"
    equal.compare(equal) | try expect_equal(expected: 0)

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
            "line boundary: {line_case.text.toString()}"
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
    (chars() != ["é", "\n", "🙂", "\n"] or lines() != ["é", "🙂"]) | try expect_false
    (reverse() != "\n🙂\né" or length() != 4 or empty()) | try expect_false
    compare(other: "é\n🙂\n") | try expect_equal(expected: 0)
    let first = lines()
    let second = lines()
    first.set(0, "changed").append("new")
    second | try expect_equal(expected: ["é", "🙂"])
    let empty_lines = "".lines()
    empty_lines.append("new")
    ("".lines().is_empty()) | try expect_true
