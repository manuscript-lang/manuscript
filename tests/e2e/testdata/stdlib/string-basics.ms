import List from "@std/collections.ms"
import panic from "@std/faults.ms"

test "String basic counterparts are callable":
    if "é🙂".length() != 2: return panic("scalar length")
    if not ("".is_empty()) or "a".is_empty(): return panic("empty text")
    if "é🙂".chars() != ["é", "🙂"]: return panic("scalar chars")
    if "é🙂".reverse() != "🙂é": return panic("scalar reverse")
    if (
        "a".compare("b") != -1
        or "b".compare("a") != 1
        or "é".compare("é") != 0
    ): return panic("text comparison")
    if "a\r\nb\n".lines() != ["a", "b"]: return panic("text lines")

test "length and chars use scalars and preserve text boundaries":
    let text = "é🙂e\u{301}"
    if text.length() != 4 or text.length() != text.scalar_length(): return panic(
        "String length unit"
    )
    if text.chars() != ["é", "🙂", "e", "\u{301}"]: return panic(
        "combining scalar chars"
    )
    if "👩\u{200d}🚀".length() != 3: return panic("graphemes are not scalars")
    if "a\u{0}b".chars() != ["a", "\u{0}", "b"]: return panic("NUL scalar lost")
    if not ("".chars().is_empty()) or "".length() != 0: return panic(
        "empty scalar collection"
    )

    let characters = text.chars()
    let second = text.chars()
    characters.set(0, "changed").append("new")
    if second != ["é", "🙂", "e", "\u{301}"] or text != "é🙂e\u{301}": return panic(
        "chars storage alias"
    )

test "reverse operates on scalars without normalization":
    if "aé🙂z".reverse() != "z🙂éa": return panic("reverse split UTF-8")
    if "e\u{301}".reverse() != "\u{301}e": return panic("reverse normalized grapheme")
    if "👩\u{200d}🚀".reverse() != "🚀\u{200d}👩": return panic("reverse grapheme unit")
    if "a\u{0}b".reverse() != "b\u{0}a": return panic("reverse lost NUL")
    if "".reverse() != "" or "🙂".reverse() != "🙂": return panic("empty/single reverse")

    let original = "é🙂e\u{301}"
    if original.reverse().reverse() != original: return panic("reverse round trip")

test "compare is normalized sign and scalar lexical order":
    if "".compare("a") != -1 or "a".compare("") != 1: return panic("empty comparison")
    if "ab".compare("abc") != -1 or "abc".compare("ab") != 1: return panic(
        "prefix comparison"
    )
    if "Z".compare("a") != -1: return panic("comparison case folding")
    if "é".compare("e\u{301}") != 1: return panic("comparison normalization")
    if "\u{e000}".compare("\u{10000}") != -1: return panic(
        "comparison used UTF-16 units"
    )
    if "a\u{0}".compare("a\u{1}") != -1: return panic("comparison NUL boundary")

    let equal = "é🙂"
    if equal.compare(equal) != 0: return panic("comparison equality")

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
        LineCase(
            "a\r\nb\nc",
            ["a", "b", "c"]
        ),
        LineCase("a\r", ["a\r"]),
        LineCase("\r", ["\r"]),
        LineCase("\r\r\n", ["\r"]),
        LineCase("a\rb", ["a\rb"]),
        LineCase("é\r\n🙂\n", ["é", "🙂"]),
        LineCase("a\u{0}\nb", ["a\u{0}", "b"]),
        LineCase("a\u{85}b\u{2028}c\u{2029}d", ["a\u{85}b\u{2028}c\u{2029}d"])
    ]

    for line_case in cases:
        if line_case.text.lines() != line_case.expected: return panic(
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
    if chars() != ["é", "\n", "🙂", "\n"] or lines() != ["é", "🙂"]: return panic(
        "bound text collection receiver"
    )
    if (
        reverse() != "\n🙂\né"
        or length() != 4
        or empty()
    ): return panic("bound scalar receiver")
    if compare(other: "é\n🙂\n") != 0: return panic("bound compare receiver/label")

    let first = lines()
    let second = lines()
    first.set(0, "changed").append("new")
    if second != ["é", "🙂"]: return panic("lines storage alias")

    let empty_lines = "".lines()
    empty_lines.append("new")
    if not ("".lines().is_empty()): return panic("empty lines storage alias")
