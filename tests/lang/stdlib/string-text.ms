// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

test "string text helpers" {
	"  a b\t c ".fields() | expect_equal(["a", "b", "c"])?
	"hello wORLD".title() | expect_equal("Hello World")?
	"xxabcxx".trim_chars("x") | expect_equal("abc")?
	"a,b,c".split_after(",") | expect_equal(["a,", "b,", "c"])?
	"Straße".equal_fold("STRASSE") | expect_equal(true)?
	"ı".equal_fold("I") | expect_equal(true)?
	"banana".count("an") | expect_equal(2)?
	"a<b>".replace_each({"<": "&lt;", ">": "&gt;"}) | expect_equal("a&lt;b&gt;")?
	"".fields() | expect_equal(List[String]())?
	"a\u{a0}b".fields() | expect_equal(["a", "b"])?
	"a1b22c".fields_by(c => c >= "0" and c <= "9") | expect_equal(["a", "b", "c"])?
	"1a22bc3".fields_by(c => c >= "0" and c <= "9") | expect_equal(["a", "bc"])?
	"123".fields_by(c => c >= "0" and c <= "9") | expect_equal(List[String]())?
	"".fields_by(c => c == " ") | expect_equal(List[String]())?
	"é 1éé  x".fields_by(c => c == " ") | expect_equal(["é", "1éé", "x"])?
	"aaa".count("") | expect_equal(4)?
	"aaaa".count("aa") | expect_equal(2)?
	"héllo".trim_start_chars("hé") | expect_equal("llo")?
	"abc".trim_end_chars("cb") | expect_equal("a")?
	"abc".contains_any("xyc") | expect_equal(true)?
	"héllo".index_any("lo") | expect_equal(3)?
	"abc".index_any("") | expect_equal(null)?
	"ab".split_after("") | expect_equal(["a", "b"])?
	"a,b,".split_after(",") | expect_equal(["a,", "b,"])?
	"élan vital".capitalize() | expect_equal("Élan vital")?
	"it's a dog".title() | expect_equal("It's A Dog")?
	"a1b".map_chars(c => if c == "1" { "" } else { c.upper() }) | expect_equal("AB")?
	"héllo".find_char(c => c == "l") | expect_equal(3)?
	"aaa".replace_each({"aa": "b", "a": "c"}) | expect_equal("bc")?
	"x".replace_each(Map[String, String]()) | expect_equal("x")?
}

test "replace_each without replacements preserves exact text" {
	pairs := Map[String, String]()

	for text in ["", "a", "héllo 🦀", "a\u{0}b", "e\u{301}"] {
		text.replace_each(pairs) | expect_equal(text)?
		text.replace_each({"": "ignored"}) | expect_equal(text)?
	}

	var source = "héllo 🦀"
	copied := source.replace_each(pairs)
	source = "changed"
	copied | expect_equal("héllo 🦀")?
	source | expect_equal("changed")?
	pairs.is_empty() | expect_equal(true)?
	"".replace_each({"a": "b"}) | expect_equal("")?
	"🦀é🦀".replace_each({"🦀": "x", "é": "y"}) | expect_equal("xyx")?
	"ab".replace_each({"a": "ab"}) | expect_equal("abb")?
}

test "replace_each scans bytes with map order, multibyte keys and unmatched runs" {
	"a&b<c>\"d'e".replace_each(
		{"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"}
	) | expect_equal("a&amp;b&lt;c&gt;&quot;d&#39;e")?
	"abcabc".replace_each({"abd": "x", "ab": "y", "c": "z"}) | expect_equal("yzyz")?
	"ab".replace_each({"a": "1", "ab": "2"}) | expect_equal("1b")?
	"ab".replace_each({"ab": "2", "a": "1"}) | expect_equal("2")?
	"aé🦀é".replace_each({"é": "e", "🦀": "crab", "": "x"}) | expect_equal("aecrabe")?
	"ééa".replace_each({"éa": "!"}) | expect_equal("é!")?
	"aaa".replace_each({"aaaa": "x"}) | expect_equal("aaa")?
	"tail a".replace_each({"a": "b"}) | expect_equal("tbil b")?
}

// The reference walks every scalar, so it shares nothing with the windowed scans.
fn reference_start(text String, set String) Int {
	var count = 0

	for c in text.chars() {
		if not set.contains(c) { return count }

		count += c.length()
	}

	return count
}

fn reference_end(text String, set String) Int {
	cs := text.chars()
	var n = text.length()
	var i = cs.length()

	while i > 0 and set.contains(cs[i - 1]) {
		n -= cs[i - 1].length()
		i -= 1
	}

	return n
}

test "char-set trims and find_char agree with a scalar walk across scan windows" {
	for lead in [0, 1, 31, 32, 33, 95, 96, 97, 300] {
		for trail in [0, 1, 31, 32, 33, 95, 96, 97, 300] {
			for core in ["", "é", "x", "xé😀y"] {
				text := ("é".repeat(lead) + core + "é".repeat(trail))
				expected_start := reference_start(text, "é")
				expected_end := reference_end(text, "é")
				expect_equal(
					text.trim_start_chars("é"),
					text.view(expected_start, text.length()),
				)?
				expect_equal(text.trim_end_chars("é"), text.view(0, expected_end))?
				expect_equal(
					text.find_char(c => c != "é"),
					if expected_start == text.length() { null } else { expected_start },
				)?

				if expected_start < expected_end {
					expect_equal(
						text.trim_chars("é"),
						text.view(expected_start, expected_end),
					)?
				} else {
					expect_equal(text.trim_chars("é"), "")?
				}
			}
		}
	}
}

test "slice and view agree on ASCII and non-ASCII text at scalar boundaries" {
	for text in ["", "abc", "é", "aé😀b"] {
		n := text.length()

		for count in [0, 1, 3, 6, 7, 100] {
			if count <= n and (count == n or text.scalar_at(count, -1) != -1) {
				expect_equal(text.view(0, count), text.slice(0, count))?
				expect_equal(text.view(count, n), text.slice(count, n))?
			} else if count > n {
				expect_equal(text.slice(0, count), text)?
			}
		}
	}
}

test "scalar_at gives the default outside the text and inside a scalar" {
	text := "aé😀b日"
	expect_equal(text.length(), 11)?
	expect_equal(text.scalar_at(0, -1), 97)?
	expect_equal(text.scalar_at(1, -1), 233)?
	expect_equal(text.scalar_at(3, -1), 128512)?
	expect_equal(text.scalar_at(8, -1), 26085)?
	for inside in [2, 4, 5, 6, 9, 10, 11, 12, -1] {
		expect_equal(text.scalar_at(inside, -1), -1)?
	}
	expect_equal(text.scalar_at(-9223372036854775807 - 1, -1), -1)?
}

test "slice bounds from the end agree with the same bounds from the start on non-ASCII text" {
	text := "aé😀b日"
	n := text.length()

	for start in [-13, -11, -8, -4, -1, 0, 3, 8, 11] {
		for end in [-13, -8, -4, -1, 0, 1, 4, 7, 11] {
			a := if start < 0 { n + start } else { start }
			b := if end < 0 { n + end } else { end }
			if a >= 0 and b >= a and b <= n {
				expect_equal(text.slice(start, end), text.slice(a, b))?
			}
		}
	}
}

test "character-set trims cover each end, non-ASCII sets, empty sets and whole-text trims" {
	"éxé—a—é".trim_chars("é—x") | expect_equal("a")?
	"  éa  é".trim_start_chars(" é") | expect_equal("a  é")?
	"é  aé  ".trim_end_chars(" é") | expect_equal("é  a")?
	"abc".trim_chars("") | expect_equal("abc")?
	"aaaa".trim_chars("a") | expect_equal("")?
	"".trim_end_chars("a") | expect_equal("")?
	"a😀b😀".trim_end_chars("😀") | expect_equal("a😀b")?
	(
		("x".repeat(100000) + "é" + "y".repeat(100000)).trim_chars("xy")
		| expect_equal("é")?
	)
}
// expect-exit: 0
// expect-tests: passed=8 failed=0
