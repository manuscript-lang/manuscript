import {escape, unescape} from "@std/html.ms"
import panic from "@std/faults.ms"

test "HTML unescape has an explicit text counterpart":
    if unescape("&lt;é&gt;&amp;") != "<é>&": return panic("HTML text unescape")

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
        if unescape(text: entity.encoded) != entity.decoded: return panic(
            "HTML reference: {entity.encoded}"
        )

test "HTML unescape applies text rules with a single decoding pass":
    if unescape("&amp &lt") != "& <": return panic("semicolonless references")
    if unescape("&ampx &notit;") != "&x ¬it;": return panic("text reference prefix")
    if unescape("&bogus; &#; &;") != "&bogus; &#; &;": return panic(
        "unrecognized references"
    )
    if unescape("&amp;lt; &amp;amp;") != "&lt; &amp;": return panic(
        "repeated reference decoding"
    )
    if unescape("<p>&amp;</p>") != "<p>&</p>": return panic("unescape parsed markup")
    if unescape("&AMP;") != "&" or unescape("&Amp;") != "&Amp;": return panic(
        "reference name case"
    )

test "HTML numeric references use replacement rules":
    if unescape("&#0;&#xD800;&#x110000;") != "\u{fffd}\u{fffd}\u{fffd}": return panic(
        "invalid numeric scalars"
    )
    if unescape("&#128;&#x80;") != "€€": return panic("HTML C1 replacement")
    if unescape("&#x10FFFF;") != "\u{10ffff}": return panic("maximum scalar reference")

fn apply[T, U](text: T, operation: fn(text: T) -> U) -> U:
    return operation(text)

test "HTML unescape stored and generic calls preserve labels":
    let convert = unescape
    let typed: fn(text: String) -> String = unescape
    if convert("&lt;") != "<" or typed(text: "&gt;") != ">": return panic(
        "stored unescape"
    )
    if apply[String, String]("&amp;", unescape) != "&": return panic("generic unescape")

test "HTML escape and unescape retain immutable text":
    let texts = ["", "<&>\"'é🙂", "&amp;lt;", "e\u{301}", "a\u{0}b", "\n\r\t"]
    for text in texts:
        if unescape(escape(text)) != text: return panic("HTML escape round trip")
    let original = "&lt;é&gt;"
    let alias = original
    let decoded = unescape(original)
    if (alias != "&lt;é&gt;" or original != alias or decoded != "<é>"): return panic(
        "unescape text alias"
    )
