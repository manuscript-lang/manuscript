import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {escape, unescape} from "@std/html.ms"

test "HTML unescape has an explicit text counterpart":
    unescape("&lt;é&gt;&amp;") | try expect_equal(expected: "<é>&")

type EntityCase:
    encoded: String
    decoded: String

test "HTML unescape recognizes named numeric and multi-scalar references":
    let cases = [
        EntityCase("", ""),
        EntityCase("plain é🙂", "plain é🙂"),
        EntityCase("&lt;&gt;&amp;&quot;&apos;", "<>&\"'"),
        EntityCase("&aacute;&eacute;&copy;", "áé©"),
        EntityCase("&#225;&#xE1;&#XE1;", "ááá"),
        EntityCase("&#x1F680;", "🚀"),
        EntityCase("&NotEqualTilde;", "\u{2242}\u{338}"),
        EntityCase("&#101;&#x301;", "e\u{301}"),
        EntityCase("&#13;&#10;", "\r\n"),
        EntityCase("&NewLine;", "\n"),
        EntityCase("a\u{0}b", "a\u{0}b")
    ]
    for entity in cases:
        if unescape(text: entity.encoded) != entity.decoded: return fail(
            "HTML reference: {entity.encoded}"
        )

test "HTML unescape applies text rules with a single decoding pass":
    unescape("&amp &lt") | try expect_equal(expected: "& <")
    unescape("&ampx &notit;") | try expect_equal(expected: "&x ¬it;")
    unescape("&bogus; &#; &;") | try expect_equal(expected: "&bogus; &#; &;")
    unescape("&amp;lt; &amp;amp;") | try expect_equal(expected: "&lt; &amp;")
    unescape("<p>&amp;</p>") | try expect_equal(expected: "<p>&</p>")
    (unescape("&AMP;") != "&" or unescape("&Amp;") != "&Amp;") | try expect_false

test "HTML numeric references use replacement rules":
    unescape("&#0;&#xD800;&#x110000;") | try expect_equal(
        expected: "\u{fffd}\u{fffd}\u{fffd}"
    )
    unescape("&#128;&#x80;") | try expect_equal(expected: "€€")
    unescape("&#x10FFFF;") | try expect_equal(expected: "\u{10ffff}")

fn apply[T, U](text: T, operation: fn(text: T) -> U) -> U:
    return operation(text)

test "HTML unescape stored and generic calls preserve labels":
    let convert = unescape
    let typed: fn(text: String) -> String = unescape
    (convert("&lt;") != "<" or typed(text: "&gt;") != ">") | try expect_false
    apply[String, String]("&amp;", unescape) | try expect_equal(expected: "&")

test "HTML escape and unescape retain immutable text":
    let texts = ["", "<&>\"'é🙂", "&amp;lt;", "e\u{301}", "a\u{0}b", "\n\r\t"]
    for text in texts:
        unescape(escape(text)) | try expect_equal(expected: text)
    let original = "&lt;é&gt;"
    let alias = original
    let decoded = unescape(original)
    (alias != "&lt;é&gt;" or original != alias or decoded != "<é>") | try expect_false
