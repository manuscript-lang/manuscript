// conform: tags=closures,control-flow,formatter,generics,interpolation,modules,parser,records,stdlib-html,stdlib-testing,strings,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/stdlib/html-unescape.ms
import (
	escape, unescape from "@std/data/html.ms",
	expect_equal, expect_false, fail from "@std/test/test.ms",
)

test "HTML unescape has an explicit text counterpart":
	expect_equal(unescape("&lt;é&gt;&amp;"), "<é>&")?

type EntityCase:
	encoded: String
	decoded: String

test "HTML unescape recognizes named numeric and multi-scalar references":
	cases := [
		EntityCase("", ""), EntityCase("plain é🙂", "plain é🙂"),
		EntityCase("&lt;&gt;&amp;&quot;&apos;", "<>&\"'"),
		EntityCase("&aacute;&eacute;&copy;", "áé©"),
		EntityCase("&#225;&#xE1;&#XE1;", "ááá"), EntityCase("&#x1F680;", "🚀"),
		EntityCase("&NotEqualTilde;", "\u{2242}\u{338}"),
		EntityCase("&#101;&#x301;", "e\u{301}"), EntityCase("&#13;&#10;", "\r\n"),
		EntityCase("&NewLine;", "\n"), EntityCase("a\u{0}b", "a\u{0}b")
	]
	for entity in cases:
		if unescape(entity.encoded) != entity.decoded: return fail(
			"HTML reference: {entity.encoded}"
		)

test "HTML unescape applies text rules with a single decoding pass":
	expect_equal(unescape("&amp &lt"), "& <")?
	expect_equal(unescape("&ampx &notit;"), "&x ¬it;")?
	expect_equal(unescape("&bogus; &#; &;"), "&bogus; &#; &;")?
	expect_equal(unescape("&amp;lt; &amp;amp;"), "&lt; &amp;")?
	expect_equal(unescape("<p>&amp;</p>"), "<p>&</p>")?
	expect_false(unescape("&AMP;") != "&" or unescape("&Amp;") != "&Amp;")?

test "HTML numeric references use replacement rules":
	expect_equal(unescape("&#0;&#xD800;&#x110000;"), "\u{fffd}\u{fffd}\u{fffd}")?
	expect_equal(unescape("&#128;&#x80;"), "€€")?
	expect_equal(unescape("&#x10FFFF;"), "\u{10ffff}")?

fn apply[T, U](text: T, operation: fn(T) U) U:
	return operation(text)

test "HTML unescape stored and generic calls preserve labels":
	convert := unescape
	typed: fn(String) String := unescape
	expect_false(convert("&lt;") != "<" or typed("&gt;") != ">")?
	expect_equal(apply[String, String]("&amp;", unescape), "&")?

test "HTML escape and unescape retain immutable text":
	texts := ["", "<&>\"'é🙂", "&amp;lt;", "e\u{301}", "a\u{0}b", "\n\r\t"]
	for text in texts:
		expect_equal(unescape(escape(text)), text)?

	original := "&lt;é&gt;"
	alias := original.clone()
	decoded := unescape(original)
	expect_false((alias != "&lt;é&gt;" or original != alias or decoded != "<é>"))?

test "HTML unescape keeps a hexadecimal reference without digits literal":
	expect_false(unescape("&#x;") != "&#x;" or unescape("&#X;") != "&#X;")?
	expect_equal(unescape("a&#x;b"), "a&#x;b")?
	expect_equal(unescape("&amp;&#x;&lt;"), "&&#x;<")?
