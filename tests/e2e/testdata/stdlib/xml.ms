import expect_equal, expect_true from "@std/test/test.ms"
import parse, stringify, escape_text, XmlNode from "@std/data/xml.ms"

test "parse reads elements attributes and text":
    let doc = parse(
        "<?xml version=\"1.0\"?>\n<!-- top --><feed a=\"1\" b='x &amp; y'><item id=\"7\">Hi &lt;there&gt; &#65;&#x42;</item><empty/></feed>\n"
    ).get()
    try expect_equal(doc.tag(), "feed")
    try expect_equal(doc.attribute("b").get(""), "x & y")

    let item = doc.find("item").get()
    try expect_equal(item.attribute("id").get(""), "7")
    try expect_equal(item.text(), "Hi <there> AB")
    try expect_equal(doc.find_all("empty").length(), 1)
    try expect_true(not doc.find("missing").is_some())

test "CDATA and comments":
    let doc = parse("<a>x<![CDATA[<raw & text>]]><!--c-->y</a>").get()
    try expect_equal(doc.text(), "x<raw & text>y")
    try expect_equal(doc.children().length(), 4)

test "stringify round-trips and escapes":
    let source = "<a k=\"v &amp; &quot;w&quot;\"><b>1 &lt; 2</b><c/></a>"
    let doc = parse(source).get()
    try expect_equal(stringify(doc), source)
    try expect_equal(parse(stringify(doc)).get().text(), "1 < 2")
    try expect_equal(escape_text("a<b&c"), "a&lt;b&amp;c")

test "indent puts elements on lines":
    let doc = parse("<a><b><c/></b><d>t</d></a>").get()
    try expect_equal(
        stringify(doc, "  "), "<a>\n  <b>\n    <c/>\n  </b>\n  <d>t</d>\n</a>\n"
    )

test "malformed documents are errors":
    for bad in [
        "<a>", "<a></b>", "<a/><b/>", "text", "<a b=1/>", "<a b=\"1\" b=\"2\"/>",
        "<a>&nope;</a>", "<a>&#xZZ;</a>", "<a><</a>", "<1a/>"
    ]:
        try expect_true(parse(bad).is_error())

test "invalid character references and unseparated attributes are errors":
    for bad in [
        "<a>&#0;</a>", "<a>&#8;</a>", "<a>&#xFFFE;</a>", "<a>&#xFFFF;</a>",
        "<a>&#+65;</a>", "<a>&#x+41;</a>", "<a b=\"1\"c=\"2\"/>"
    ]:
        try expect_true(parse(bad).is_error())

    let ok = parse("<a>&#9;&#xA;&#x10FFFF;</a>").get()
    try expect_equal(ok.text(), "\t\n\u{10FFFF}")

test "depth limit":
    try expect_true(parse("<a><b><c/></b></a>", max_depth: 2).is_error())
    try expect_true(parse("<a/>", max_depth: 0).is_error())
    try expect_equal(parse("<a><b/></a>", max_depth: 2).get().tag(), "a")

test "entity decoding is linear in the text":
    let node = parse("<a>&amp;&lt;&#65;&#x42;tail</a>").get()
    try expect_equal(node.text(), "&<ABtail")
    try expect_true(parse("<a>&amp</a>").is_error())
    try expect_true(parse("<a>&nope;</a>").is_error())

    // A quadratic decoder would take minutes on this many entities.
    let big = parse("<a>{"&amp;".repeat(100000).get()}</a>").get()
    try expect_equal(big.text().scalar_length(), 100000)

test "malformed comments fail inside before and after the root":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))

    for comment in [
        "<!--a--b-->", "<!--a--->", "<!--a\n--b-->", "<!--a---->", "<!--open"
    ]:
        try expect_equal(parse("<a>{comment}</a>"), malformed)
        try expect_equal(parse("{comment}<a/>"), malformed)
        try expect_equal(parse("<a/>{comment}"), malformed)

test "valid comments preserve text and leave other delimited constructs alone":
    for contents in ["", "a-b", "-a", "a\n-b", "é - 😀", "&amp; &#65;"]:
        let comment = "<!--{contents}-->"
        let inside = "<a>{comment}</a>"
        let node = try parse(inside)
        try expect_equal(node.children(), [XmlNode.XmlComment(contents.clone())])
        try expect_equal(stringify(node), inside)
        try expect_equal(stringify(try parse("{comment}<a/>{comment}")), "<a/>")

    let node = try parse("<a><!----><!--a-b--><![CDATA[x--y]]><?p x--y?></a>")
    try expect_equal(node.children().length(), 3)
    try expect_equal(node.text(), "x--y")

test "literal XML characters obey the same ranges as character references":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))

    for invalid in [
        "\u{0}", "\u{1}", "\u{8}", "\u{b}", "\u{c}", "\u{e}", "\u{1f}", "\u{fffe}",
        "\u{ffff}"
    ]:
        try expect_equal(parse("<a>{invalid}</a>"), malformed)
        try expect_equal(parse("<a v='{invalid}'/>"), malformed)
        try expect_equal(parse("<a><![CDATA[{invalid}]]></a>"), malformed)
        try expect_equal(parse("<!--{invalid}--><a/>"), malformed)
        try expect_equal(parse("<a/><?p {invalid}?>"), malformed)
        try expect_equal(parse("<!DOCTYPE a [<!ENTITY x '{invalid}'>]><a/>"), malformed)

        let code = invalid.scalar_values()[0]
        try expect_equal(parse("<a>&#{code};</a>"), malformed)

    for valid in [
        "\t", "\n", "\r", " ", "\u{7f}", "\u{85}", "\u{9f}", "\u{d7ff}", "\u{e000}",
        "\u{fffd}", "\u{10000}", "\u{10ffff}"
    ]:
        try expect_true(parse("<a>{valid}</a>").is_ok())
        try expect_true(parse("<a v='{valid}'/>").is_ok())
        try expect_true(parse("<a><![CDATA[{valid}]]></a>").is_ok())
        try expect_true(parse("<!--{valid}--><a/>").is_ok())
        try expect_true(parse("<a/><?p {valid}?>").is_ok())
        try expect_true(parse("<!DOCTYPE a [<!ENTITY x '{valid}'>]><a/>").is_ok())

        let code = valid.scalar_values()[0]
        try expect_true(parse("<a>&#{code};</a>").is_ok())

    try expect_true(parse("\u{feff}<a/>").is_ok())

test "CDATA terminators are forbidden only in literal character data":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))

    for text in ["]]>right", "left]]>", "left]]>right", "]]]>", "]]>"]:
        try expect_equal(parse("<a>{text}</a>"), malformed)
        try expect_equal(parse("<a><b/>{text}</a>"), malformed)

    for text in ["]]&gt;", "&#93;]>", "]&#93;>", "]]<b/>>", "]<!--c-->]>"]:
        try expect_equal((try parse("<a>{text}</a>")).text(), "]]>")

    let attribute = try parse("<a v=']]>'/>")
    try expect_equal(attribute.attribute("v").get(""), "]]>")
    try expect_equal((try parse("<a><![CDATA[]]]]><![CDATA[>]]></a>")).text(), "]]>")
    for text in ["]]", "]>", "]"]:
        try expect_equal((try parse("<a>{text}</a>")).text(), text)
