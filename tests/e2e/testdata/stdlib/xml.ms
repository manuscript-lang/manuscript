import (
    from_scalars from "@std/string.ms",
    expect_equal, expect_true from "@std/test/test.ms",
    parse, stringify, escape_text, XmlNode, XmlAttribute from "@std/data/xml.ms",
)

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
    try expect_true(doc.find("missing").is_none())

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

test "stringify preserves compact and mixed content formatting":
    for source in [
        "<a/>", "<a>text<b/></a>", "<a><b/>text</a>", "<a> <b/> </a>",
        "<a><!--comment-->text<b/></a>", "<a><b/>text<!--comment--></a>",
        "<é:root attr=\"&amp;&quot;&#9;&#10;&#13;\">]]&gt;<日/></é:root>"
    ]:
        let doc = try parse(source)
        try expect_equal(stringify(doc), source)
        try expect_equal(stringify(doc, "  "), "{source}\n")

test "stringify leaves comments and descendant text on indented lines":
    let doc = try parse("<a><!--comment--><b>text</b><c/></a>")
    try expect_equal(
        stringify(doc, "  "), "<a>\n  <!--comment-->\n  <b>text</b>\n  <c/>\n</a>\n"
    )

    let empty = XmlNode.XmlElement("a", [], [XmlNode.XmlText("")])
    try expect_equal(stringify(empty), "<a></a>")
    try expect_equal(stringify(empty, "  "), "<a>\n</a>\n")

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

test "processing instructions require a name and whitespace before data":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))

    for instruction in [
        "<??>", "<? ?>", "<?1bad?>", "<?@?>", "<?p!data?>", "<?p/data?>", "<?p=data?>",
        "<?p\u{a0}data?>", "<?p", "<?p data"
    ]:
        try expect_equal(parse("{instruction}<a/>"), malformed)
        try expect_equal(parse("<a>{instruction}</a>"), malformed)
        try expect_equal(parse("<a/>{instruction}"), malformed)

    for instruction in [
        "<?p?>", "<?p ?>", "<?p\tdata?>", "<?p\r\ndata?>",
        "<?xml-stylesheet href='style.xsl'?>", "<?xmlfoo?>", "<?XML:task?>",
        "<?é:task data &literal; <markup> ? more?>"
    ]:
        try expect_equal(stringify(try parse("{instruction}<a/>{instruction}")), "<a/>")
        try expect_equal((try parse("<a>x{instruction}y</a>")).text(), "xy")

test "XML declarations occur only at the document start":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))
    let declaration = "<?xml version='1.0'?>"

    for target in ["xml", "XML", "Xml", "xMl", "xmL", "XMl", "xML", "XmL"]:
        try expect_equal(parse("<a><?{target} version='1.0'?></a>"), malformed)
        try expect_equal(parse("<a/><?{target} version='1.0'?>"), malformed)
        if target != "xml":
            try expect_equal(parse("<?{target} version='1.0'?><a/>"), malformed)

    for prefix in [" ", "\n", "<!--c-->", "<?p?>", declaration.clone()]:
        try expect_equal(parse("{prefix}{declaration}<a/>"), malformed)
    try expect_equal((try parse("{declaration}<a/>")).tag(), "a")
    try expect_equal((try parse("\u{feff}{declaration}<a/>")).tag(), "a")

test "XML declarations validate ordered literal pseudo attributes":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))
    for declaration in [
        "<?xml?>", "<?xml ?>", "<?xml encoding='UTF-8'?>", "<?xml version=1.0?>",
        "<?xml version='1.0?>", "<?xml version='2.0'?>", "<?xml version='1.'?>",
        "<?xml version='1.a'?>", "<?xml version='1.0.0'?>", "<?xml version=' 1.0'?>",
        "<?xml version='1.&#48;'?>", "<?xml version='1.0'encoding='UTF-8'?>",
        "<?xml version='1.0' version='1.0'?>", "<?xml version='1.0' other='x'?>",
        "<?xml version='1.0' encoding=''?>", "<?xml version='1.0' encoding='8UTF'?>",
        "<?xml version='1.0' encoding='UTF 8'?>", "<?xml version='1.0' encoding='é'?>",
        "<?xml version='1.0' encoding='UTF:8'?>",
        "<?xml version='1.0' encoding='UTF-8' encoding='UTF-8'?>",
        "<?xml version='1.0' standalone='true'?>",
        "<?xml version='1.0' standalone='YES'?>",
        "<?xml version='1.0' standalone='yes' standalone='no'?>",
        "<?xml version='1.0' standalone='yes' encoding='UTF-8'?>"
    ]:
        try expect_equal(parse("{declaration}<a/>"), malformed)
    for declaration in [
        "<?xml version='1.0'?>", "<?xml version = \"1.0\" ?>",
        "<?xml\tversion\n=\r'1.0'\nencoding = 'UTF-8'\tstandalone='yes' ?>",
        "<?xml version='1.0' standalone='no'?>",
        "<?xml version='1.0' encoding='UTF-8'?>",
        "<?xml version='1.0' encoding='x-custom_1.2' standalone='no'?>",
        "<?xml version='1.1'?>", "<?xml version='1.17'?>"
    ]:
        try expect_equal((try parse("{declaration}<a/>")).tag(), "a")

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

test "XML name starts follow every XML 1.0 range boundary":
    for code in [
        0x3a, 0x41, 0x5a, 0x5f, 0x61, 0x7a, 0xc0, 0xd6, 0xd8, 0xf6, 0xf8, 0x2ff, 0x370,
        0x37d, 0x37f, 0x1fff, 0x200c, 0x200d, 0x2070, 0x218f, 0x2c00, 0x2fef, 0x3001,
        0xd7ff, 0xf900, 0xfdcf, 0xfdf0, 0xfffd, 0x10000, 0xeffff
    ]:
        let scalar = try from_scalars([code])

        for name in [scalar.clone(), "a{scalar}"]:
            let element = try parse("<{name}></{name}>")
            try expect_equal(element.tag(), name)

            let attribute = try parse("<a {name}='value'/>")
            try expect_equal(attribute.attribute(name).get(""), "value")

test "XML continuation-only scalars cannot start a name":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))

    for code in [0x2d, 0x2e, 0x30, 0x39, 0xb7, 0x300, 0x36f, 0x203f, 0x2040]:
        let scalar = try from_scalars([code])
        try expect_equal(parse("<{scalar}/>"), malformed)
        try expect_equal(parse("<a {scalar}='value'/>"), malformed)

        let name = "a{scalar}"
        try expect_equal((try parse("<{name}></{name}>")).tag(), name)
        try expect_equal(
            (try parse("<a {name}='value'/>")).attribute(name).get(""), "value"
        )

test "XML names reject punctuation and excluded Unicode gaps":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))

    for code in [
        0x23, 0x24, 0x25, 0x2b, 0x40, 0x5b, 0x5c, 0x5d, 0x5e, 0x60, 0x7b, 0x7c, 0x7d,
        0x7e, 0x7f, 0xb6, 0xb8, 0xbf, 0xd7, 0xf7, 0x37e, 0x2000, 0x200b, 0x200e, 0x203e,
        0x2041, 0x206f, 0x2190, 0x2bff, 0x2ff0, 0x3000, 0xe000, 0xf8ff, 0xfdd0, 0xfdef,
        0xf0000, 0x10ffff
    ]:
        let scalar = try from_scalars([code])

        for name in [scalar.clone(), "a{scalar}"]:
            try expect_equal(parse("<{name}/>"), malformed)
            try expect_equal(parse("<a {name}='value'/>"), malformed)

test "line ends normalize to newline and attribute whitespace to spaces":
    let doc = parse("<a k=\"x\ny\tz\r\nw\">t\r\nu\rv<![CDATA[c\r\nd]]></a>").get()
    try expect_equal(doc.text(), "t\nu\nvc\nd")
    try expect_equal(doc.attribute("k").get(""), "x y z w")

test "character references keep whitespace that normalization would change":
    let doc = parse("<a k=\"x&#10;y&#9;z&#13;\">&#13;&#10;</a>").get()
    try expect_equal(doc.attribute("k").get(""), "x\ny\tz\r")
    try expect_equal(doc.text(), "\r\n")

test "carriage returns survive a stringify and parse round trip":
    let source = XmlElement("a", [XmlAttribute("k", "p\rq\nr\ts")], [XmlText("t\r\nu")])
    let text = stringify(source)
    try expect_true(not text.contains("\r"))

    let back = parse(text).get()
    try expect_equal(back.text(), "t\r\nu")
    try expect_equal(back.attribute("k").get(""), "p\rq\nr\ts")

test "DOCTYPE skipping honors quoted spans and prolog placement":
    for accepted in [
        "<!DOCTYPE a SYSTEM \"a>b\"><a/>", "<!DOCTYPE a SYSTEM 'a>b'><a/>",
        "<!DOCTYPE a PUBLIC \"-//x//y\" \"u]>v\"><a/>",
        "<!DOCTYPE a [<!ENTITY x \"]>\">]><a/>",
        "<!DOCTYPE a [<!-- ]> --><!ELEMENT a EMPTY>]><a/>",
        "<!DOCTYPE a [<?p ]> ?><!ELEMENT a EMPTY>]><a/>", "<!DOCTYPE a [%e;]><a/>",
        "<?xml version=\"1.0\"?><!--c--><!DOCTYPE a><!--d--><a/>"
    ]:
        try expect_true(parse(accepted).is_ok())
    for rejected in [
        "<a/><!DOCTYPE a>", "<!DOCTYPE a><!DOCTYPE a><a/>", "<!DOCTYPEa><a/>",
        "<!DOCTYPE><a/>", "<!DOCTYPE a SYSTEM><a/>",
        "<!DOCTYPE a [<!ENTITY x \"]>]><a/>", "<!DOCTYPE a [<!ELEMENT a EMPTY><a/>"
    ]:
        try expect_true(parse(rejected).is_error())

test "DOCTYPE public identifiers accept only XML PubidChar scalars":
    let malformed: XmlNode! = error(Error("XML: invalid data", kind: "EBADMSG"))

    for quote in ["\"", "'"]:
        for invalid in ["[", "]", "<", ">", "&", "\t", "é", "😀", "\"", "\\", "\{", "\}"]:
            try expect_equal(invalid.length(), 1)
            if invalid == quote: continue

            let source = "<!DOCTYPE a PUBLIC {quote}{invalid}{quote} 'unused'><a/>"
            try expect_equal(parse(source), malformed)

        for valid in [
            "", "azAZ09", " \r\n-()+,./:=?;!*#@$_%", "-//W3C//DTD XHTML 1.0 Strict//EN"
        ]:
            let source = "<!DOCTYPE a PUBLIC {quote}{valid}{quote} 'unused'><a/>"
            try expect_equal((try parse(source)).tag(), "a")

    try expect_true(parse("<!DOCTYPE a PUBLIC \"apostrophe's\" 'unused'><a/>").is_ok())

    // A system literal has a different grammar; brackets and Unicode stay legal there.
    try expect_true(parse("<!DOCTYPE a SYSTEM 'é[<&>😀'><a/>").is_ok())
    try expect_true(parse("<!DOCTYPE a PUBLIC 'valid' 'é[<&>😀'><a/>").is_ok())

test "elements with many attributes keep their order and reject duplicates at any position":
    var text = "<root"
    for i in 0..40:
        text += " a{i}=\"{i}\""

    let doc = parse(text + "/>").get()
    try expect_equal(doc.attribute("a0").get(""), "0")
    try expect_equal(doc.attribute("a39").get(""), "39")
    try expect_equal(doc.attribute("a15").get(""), "15")
    try expect_equal(doc.attribute("a16").get(""), "16")

    // The 16th attribute is the first one checked through the set, and its list-scanned predecessors count.
    try expect_true(parse(text + " a0=\"x\"/>").is_error())
    try expect_true(parse(text + " a16=\"x\"/>").is_error())
    try expect_true(parse(text + " a39=\"x\"/>").is_error())
    try expect_true(parse(text + " a40=\"x\"/>").is_ok())
    try expect_true(parse("<root a=\"1\" b=\"2\" a=\"3\"/>").is_error())
