import expect_equal, expect_ok from "@std/test/test.ms"

test "fields omit empty items and preserve exact text":
	"".fields() | expect_equal(List[String]())?
	" \t\r\n".fields() | expect_equal(List[String]())?
	"\t alpha  beta\r\n gamma \t".fields() | expect_equal(["alpha", "beta", "gamma"])?
	"é\u{a0}🙂\u{2003}e\u{301}".fields() | expect_equal(["é", "🙂", "e\u{301}"])?
	"a\u{0}b c".fields() | expect_equal(["a\u{0}b", "c"])?
	"a\u{200b}b c\u{feff}d".fields() | expect_equal(["a\u{200b}b", "c\u{feff}d"])?

test "fields recognize the complete Unicode whitespace set":
	spaces := [
		"\t", "\n", "\u{b}", "\u{c}", "\r", " ", "\u{85}", "\u{a0}", "\u{1680}",
		"\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}",
		"\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200a}", "\u{2028}",
		"\u{2029}", "\u{202f}", "\u{205f}", "\u{3000}"
	]
	for space in spaces:
		"{space}a{space}{space}é{space}".fields() | expect_equal(["a", "é"])?

test "fields work as a bound method and return independent results":
	text := " alpha é "
	fields := text.fields
	var first = fields()
	first.set(0, "changed")
	fields() | expect_equal(["alpha", "é"])?
	text | expect_equal(" alpha é ")?

test "fields handle large inputs and separator-heavy text":
	word := "é".repeat(65536) | expect_ok?
	"  ".concat(word).concat("\u{2003}🙂 ").fields() | expect_equal([word, "🙂"])?

	separators := "\u{a0} \t".repeat(65536) | expect_ok?
	separators.fields() | expect_equal(List[String]())?
