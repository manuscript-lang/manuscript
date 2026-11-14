// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

test "string text helpers":
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
	"a1b22c".fields_by(fn c: c >= "0" and c <= "9") | expect_equal(["a", "b", "c"])?
	"1a22bc3".fields_by(fn c: c >= "0" and c <= "9") | expect_equal(["a", "bc"])?
	"123".fields_by(fn c: c >= "0" and c <= "9") | expect_equal(List[String]())?
	"".fields_by(fn c: c == " ") | expect_equal(List[String]())?
	"é 1éé  x".fields_by(fn c: c == " ") | expect_equal(["é", "1éé", "x"])?
	"aaa".count("") | expect_equal(4)?
	"aaaa".count("aa") | expect_equal(2)?
	"héllo".trim_start_chars("hé") | expect_equal("llo")?
	"abc".trim_end_chars("cb") | expect_equal("a")?
	"abc".contains_any("xyc") | expect_equal(true)?
	"héllo".index_any("lo") | expect_equal(2)?
	"abc".index_any("") | expect_equal(none)?
	"ab".split_after("") | expect_equal(["a", "b"])?
	"a,b,".split_after(",") | expect_equal(["a,", "b,"])?
	"élan vital".capitalize() | expect_equal("Élan vital")?
	"it's a dog".title() | expect_equal("It's A Dog")?
	"a1b".map_chars(fn c: if c == "1": "" else: c.upper()) | expect_equal("AB")?
	"héllo".find_char(fn c: c == "l") | expect_equal(2)?
	"aaa".replace_each({"aa": "b", "a": "c"}) | expect_equal("bc")?
	"x".replace_each(Map[String, String]()) | expect_equal("x")?

test "replace_each without replacements preserves exact text":
	pairs := Map[String, String]()

	for text in ["", "a", "héllo 🦀", "a\u{0}b", "e\u{301}"]:
		text.replace_each(pairs) | expect_equal(text)?
		text.replace_each({"": "ignored"}) | expect_equal(text)?

	var source = "héllo 🦀"
	copied := source.replace_each(pairs)
	source = "changed"
	copied | expect_equal("héllo 🦀")?
	source | expect_equal("changed")?
	pairs.is_empty() | expect_equal(true)?
	"".replace_each({"a": "b"}) | expect_equal("")?
	"🦀é🦀".replace_each({"🦀": "x", "é": "y"}) | expect_equal("xyx")?
	"ab".replace_each({"a": "ab"}) | expect_equal("abb")?

// The reference walks every scalar, so it shares nothing with the windowed scans.
fn reference_start(text: String, set: String) Int:
	var count = 0

	for c in text.chars():
		if not set.contains(c): return count

		count += 1

	return count

fn reference_end(text: String, set: String) Int:
	cs := text.chars()
	var n = cs.length()
	while n > 0 and set.contains(cs[n - 1]):
		n -= 1
	return n

test "char-set trims and find_char agree with a scalar walk across scan windows":
	for lead in [0, 1, 31, 32, 33, 95, 96, 97, 300]:
		for trail in [0, 1, 31, 32, 33, 95, 96, 97, 300]:
			for core in ["", "é", "x", "xé😀y"]:
				text := (
					"é".repeat(lead, none).get("")
					+ core
					+ "é".repeat(trail, none).get("")
				)
				expected_start := reference_start(text, "é")
				expected_end := reference_end(text, "é")
				expect_equal(text.trim_start_chars("é"), text.drop(expected_start))?
				expect_equal(text.trim_end_chars("é"), text.take(expected_end))?
				expect_equal(
					text.find_char(fn c: c != "é"),
					if expected_start == text.length(): none else: expected_start,
				)?

				if expected_start < expected_end:
					expect_equal(
						text.trim_chars("é"),
						text.take(expected_end).drop(
							expected_start
						),
					)?
				else:
					expect_equal(text.trim_chars("é"), "")?

test "take and drop clamp on ASCII and non-ASCII text":
	for text in ["", "abc", "é", "aé😀b"]:
		n := text.length()

		for count in [0, 1, 2, 3, 4, 5, 100]:
			kept := if count < n: count else: n
			expect_equal(text.take(count), text.slice(0, kept).get(""))?
			expect_equal(text.drop(count), text.slice(kept, n).get(""))?

test "negative get and scalar_at index from the end on non-ASCII text":
	text := "aé😀b日"

	for back in [1, 2, 3, 4, 5]:
		at := text.length() - back
		expect_equal(text.get(-back), text.get(at))?
		expect_equal(text.scalar_at(-back), text.scalar_at(at))?

	expect_equal(text.get(-6, "none"), "none")?
	expect_equal(text.scalar_at(-6, -1), -1)?
	expect_equal(text.get(-9223372036854775807 - 1, "none"), "none")?

test "slice bounds from the end agree with the same bounds from the start on non-ASCII text":
	text := "aé😀b日"
	n := text.length()

	for start in [-7, -6, -5, -3, -1, 0, 2, 5, 6]:
		for end in [-7, -5, -2, -1, 0, 1, 4, 5, 6]:
			a := if start < 0: n + start else: start
			b := if end < 0: n + end else: end

			if a < 0 or b < a or b > n:
				expect_true(text.slice(start, end).is_error())?
			else:
				expect_equal(text.slice(start, end).get(""), text.slice(a, b).get(""))?

test "character-set trims cover each end, non-ASCII sets, empty sets and whole-text trims":
	"éxé—a—é".trim_chars("é—x") | expect_equal("a")?
	"  éa  é".trim_start_chars(" é") | expect_equal("a  é")?
	"é  aé  ".trim_end_chars(" é") | expect_equal("é  a")?
	"abc".trim_chars("") | expect_equal("abc")?
	"aaaa".trim_chars("a") | expect_equal("")?
	"".trim_end_chars("a") | expect_equal("")?
	"a😀b😀".trim_end_chars("😀") | expect_equal("a😀b")?
	("x".repeat(100000).get("") + "é" + "y".repeat(100000).get("")).trim_chars("xy") | expect_equal("é")?
