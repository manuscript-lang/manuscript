import expect_equal, expect_true from "@std/test/test.ms"
import parse, stringify, escape_text, XmlNode, XmlError from "@std/data/xml.ms"

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

test "depth limit":
    try expect_true(parse("<a><b><c/></b></a>", max_depth: 2).is_error())
    try expect_true(parse("<a/>", max_depth: 0).is_error())
    try expect_equal(parse("<a><b/></a>", max_depth: 2).get().tag(), "a")
