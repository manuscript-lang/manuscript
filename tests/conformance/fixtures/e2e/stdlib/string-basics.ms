// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false, fail from "@std/test/test.ms"

test "Unicode lowercase sigma ignores combining marks and format characters":
	for mark in ["\u{1ab0}", "\u{5bf}", "\u{2060}", "\u{fe0f}"]:
		expect_equal("A{mark}Σ".lower(), "a{mark}ς")?
		expect_equal("AΣ{mark}A".lower(), "aσ{mark}a")?

		lower := "AΣ{mark}A".lower
		expect_equal(lower(), "aσ{mark}a")?

test "String basic counterparts are callable":
	expect_equal("é🙂".length(), 2)?
	expect_false(not ("".is_empty()) or "a".is_empty())?
	expect_equal("é🙂".chars(), ["é", "🙂"])?
	expect_equal("é🙂".reverse(), "🙂é")?
	expect_false(
		(
			"a".compare("b") != -1
			or "b".compare("a") != 1
			or "é".compare("é") != 0
		)
	)?
	expect_equal("a\r\nb\n".lines(), ["a", "b"])?

test "length and chars use scalars and preserve text boundaries":
	text := "é🙂e\u{301}"
	expect_false(text.length() != 4 or text.length() != text.scalar_length())?
	expect_equal(text.chars(), ["é", "🙂", "e", "\u{301}"])?
	expect_equal("👩\u{200d}🚀".length(), 3)?
	expect_equal("a\u{0}b".chars(), ["a", "\u{0}", "b"])?
	expect_false(not ("".chars().is_empty()) or "".length() != 0)?

	var characters = text.chars().clone()
	second := text.chars()
	characters.set(0, "changed")
	characters.append("new")
	expect_false(second != ["é", "🙂", "e", "\u{301}"] or text != "é🙂e\u{301}")?

test "reverse operates on scalars without normalization":
	expect_equal("aé🙂z".reverse(), "z🙂éa")?
	expect_equal("e\u{301}".reverse(), "\u{301}e")?
	expect_equal("👩\u{200d}🚀".reverse(), "🚀\u{200d}👩")?
	expect_equal("a\u{0}b".reverse(), "b\u{0}a")?
	expect_false("".reverse() != "" or "🙂".reverse() != "🙂")?

	original := "é🙂e\u{301}"
	expect_equal(original.reverse().reverse(), original)?

test "compare is normalized sign and scalar lexical order":
	expect_false("".compare("a") != -1 or "a".compare("") != 1)?
	expect_false("ab".compare("abc") != -1 or "abc".compare("ab") != 1)?
	expect_equal("Z".compare("a"), -1)?
	expect_equal("é".compare("e\u{301}"), 1)?
	expect_equal("\u{e000}".compare("\u{10000}"), -1)?
	expect_equal("a\u{0}".compare("a\u{1}"), -1)?

	equal := "é🙂"
	expect_equal(equal.compare(equal), 0)?

type LineCase:
	text: String
	expected: List[String]

test "lines preserve interior empties and recognize LF and CRLF only":
	cases := [
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
		LineCase("a\u{85}b\u{2028}c\u{2029}d", ["a\u{85}b\u{2028}c\u{2029}d"]),
	]
	for line_case in cases:
		if line_case.text.lines() != line_case.expected: return fail(
			"line boundary: {line_case.text.to_string()}"
		)

test "String basic bound methods capture immutable receiver values":
	var text = "é\n🙂\n"

	// A method value borrows its receiver, so a snapshot that outlives a change is a
	// clone.
	snapshot := text.clone()
	chars := snapshot.chars
	lines := snapshot.lines
	reverse := snapshot.reverse
	length := snapshot.length
	empty := snapshot.is_empty
	compare := snapshot.compare
	text = "changed"
	expect_false(chars() != ["é", "\n", "🙂", "\n"] or lines() != ["é", "🙂"])?
	expect_false((reverse() != "\n🙂\né" or length() != 4 or empty()))?
	expect_equal(compare("é\n🙂\n"), 0)?

	var first = lines()
	second := lines()
	first.set(0, "changed")
	first.append("new")
	expect_equal(second, ["é", "🙂"])?

	var empty_lines = "".lines()
	empty_lines.append("new")
	expect_false(not ("".lines().is_empty()))?
