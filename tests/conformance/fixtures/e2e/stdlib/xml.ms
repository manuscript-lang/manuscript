// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	XmlAttribute, XmlNode, escape_text, parse, stringify from "@std/data/xml.ms",
	from_scalars from "@std/string.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "parse reads elements attributes and text":
	doc := parse(
		"<?xml version=\"1.0\"?>\n<!-- top --><feed a=\"1\" b='x &amp; y'><item id=\"7\">Hi &lt;there&gt; &#65;&#x42;</item><empty/></feed>\n"
	).get()
	expect_equal(doc.tag(), "feed")?
	expect_equal(doc.attribute("b").get(""), "x & y")?

	item := doc.find("item").get()
	expect_equal(item.attribute("id").get(""), "7")?
	expect_equal(item.text(), "Hi <there> AB")?
	expect_equal(doc.find_all("empty").length(), 1)?
	expect_true(doc.find("missing").is_none())?

test "CDATA and comments":
	doc := parse("<a>x<![CDATA[<raw & text>]]><!--c-->y</a>").get()
	expect_equal(doc.text(), "x<raw & text>y")?
	expect_equal(doc.children().length(), 4)?

test "stringify round-trips and escapes":
	source := "<a k=\"v &amp; &quot;w&quot;\"><b>1 &lt; 2</b><c/></a>"
	doc := parse(source).get()
	expect_equal(stringify(doc), source)?
	expect_equal(parse(stringify(doc)).get().text(), "1 < 2")?
	expect_equal(escape_text("a<b&c"), "a&lt;b&amp;c")?

test "indent puts elements on lines":
	doc := parse("<a><b><c/></b><d>t</d></a>").get()
	expect_equal(
		stringify(doc, "  "),
		"<a>\n  <b>\n    <c/>\n  </b>\n  <d>t</d>\n</a>\n",
	)?

test "stringify preserves compact and mixed content formatting":
	for source in [
		"<a/>", "<a>text<b/></a>", "<a><b/>text</a>", "<a> <b/> </a>",
		"<a><!--comment-->text<b/></a>", "<a><b/>text<!--comment--></a>",
		"<é:root attr=\"&amp;&quot;&#9;&#10;&#13;\">]]&gt;<日/></é:root>"
	]:
		doc := parse(source)?
		expect_equal(stringify(doc), source)?
		expect_equal(stringify(doc, "  "), "{source}\n")?

test "stringify leaves comments and descendant text on indented lines":
	doc := parse("<a><!--comment--><b>text</b><c/></a>")?
	expect_equal(
		stringify(doc, "  "),
		"<a>\n  <!--comment-->\n  <b>text</b>\n  <c/>\n</a>\n",
	)?

	empty := XmlNode.XmlElement("a", [], [XmlNode.XmlText("")])
	expect_equal(stringify(empty), "<a></a>")?
	expect_equal(stringify(empty, "  "), "<a>\n</a>\n")?

test "malformed documents are errors":
	for bad in [
		"<a>", "<a></b>", "<a/><b/>", "text", "<a b=1/>", "<a b=\"1\" b=\"2\"/>",
		"<a>&nope;</a>", "<a>&#xZZ;</a>", "<a><</a>", "<1a/>"
	]:
		expect_true(parse(bad).is_error())?

test "invalid character references and unseparated attributes are errors":
	for bad in [
		"<a>&#0;</a>", "<a>&#8;</a>", "<a>&#xFFFE;</a>", "<a>&#xFFFF;</a>",
		"<a>&#+65;</a>", "<a>&#x+41;</a>", "<a b=\"1\"c=\"2\"/>"
	]:
		expect_true(parse(bad).is_error())?

	ok := parse("<a>&#9;&#xA;&#x10FFFF;</a>").get()
	expect_equal(ok.text(), "\t\n\u{10FFFF}")?

test "depth limit":
	expect_true(parse("<a><b><c/></b></a>", max_depth: 2).is_error())?
	expect_true(parse("<a/>", max_depth: 0).is_error())?
	expect_equal(parse("<a><b/></a>", max_depth: 2).get().tag(), "a")?

test "processing instructions require a name and whitespace before data":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))

	for instruction in [
		"<??>", "<? ?>", "<?1bad?>", "<?@?>", "<?p!data?>", "<?p/data?>", "<?p=data?>",
		"<?p\u{a0}data?>", "<?p", "<?p data"
	]:
		expect_equal(parse("{instruction}<a/>"), malformed)?
		expect_equal(parse("<a>{instruction}</a>"), malformed)?
		expect_equal(parse("<a/>{instruction}"), malformed)?

	for instruction in [
		"<?p?>", "<?p ?>", "<?p\tdata?>", "<?p\r\ndata?>",
		"<?xml-stylesheet href='style.xsl'?>", "<?xmlfoo?>", "<?XML:task?>",
		"<?é:task data &literal; <markup> ? more?>"
	]:
		expect_equal(stringify(parse("{instruction}<a/>{instruction}")?), "<a/>")?
		expect_equal((parse("<a>x{instruction}y</a>")?).text(), "xy")?

test "XML declarations occur only at the document start":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))
	declaration := "<?xml version='1.0'?>"

	for target in ["xml", "XML", "Xml", "xMl", "xmL", "XMl", "xML", "XmL"]:
		expect_equal(parse("<a><?{target} version='1.0'?></a>"), malformed)?
		expect_equal(parse("<a/><?{target} version='1.0'?>"), malformed)?
		if target != "xml":
			expect_equal(parse("<?{target} version='1.0'?><a/>"), malformed)?

	for prefix in [" ", "\n", "<!--c-->", "<?p?>", declaration.clone()]:
		expect_equal(parse("{prefix}{declaration}<a/>"), malformed)?
	expect_equal((parse("{declaration}<a/>")?).tag(), "a")?
	expect_equal((parse("\u{feff}{declaration}<a/>")?).tag(), "a")?

test "XML declarations validate ordered literal pseudo attributes":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))
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
		expect_equal(parse("{declaration}<a/>"), malformed)?
	for declaration in [
		"<?xml version='1.0'?>", "<?xml version = \"1.0\" ?>",
		"<?xml\tversion\n=\r'1.0'\nencoding = 'UTF-8'\tstandalone='yes' ?>",
		"<?xml version='1.0' standalone='no'?>",
		"<?xml version='1.0' encoding='UTF-8'?>",
		"<?xml version='1.0' encoding='x-custom_1.2' standalone='no'?>",
		"<?xml version='1.1'?>", "<?xml version='1.17'?>"
	]:
		expect_equal((parse("{declaration}<a/>")?).tag(), "a")?

test "entity decoding is linear in the text":
	node := parse("<a>&amp;&lt;&#65;&#x42;tail</a>").get()
	expect_equal(node.text(), "&<ABtail")?
	expect_true(parse("<a>&amp</a>").is_error())?
	expect_true(parse("<a>&nope;</a>").is_error())?

	// A quadratic decoder would take minutes on this many entities.
	big := parse("<a>{"&amp;".repeat(100000).get()}</a>").get()
	expect_equal(big.text().scalar_length(), 100000)?

test "malformed comments fail inside before and after the root":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))

	for comment in [
		"<!--a--b-->", "<!--a--->", "<!--a\n--b-->", "<!--a---->", "<!--open"
	]:
		expect_equal(parse("<a>{comment}</a>"), malformed)?
		expect_equal(parse("{comment}<a/>"), malformed)?
		expect_equal(parse("<a/>{comment}"), malformed)?

test "valid comments preserve text and leave other delimited constructs alone":
	for contents in ["", "a-b", "-a", "a\n-b", "é - 😀", "&amp; &#65;"]:
		comment := "<!--{contents}-->"
		inside := "<a>{comment}</a>"
		node := parse(inside)?
		expect_equal(node.children(), [XmlNode.XmlComment(contents.clone())])?
		expect_equal(stringify(node), inside)?
		expect_equal(stringify(parse("{comment}<a/>{comment}")?), "<a/>")?

	node := parse("<a><!----><!--a-b--><![CDATA[x--y]]><?p x--y?></a>")?
	expect_equal(node.children().length(), 3)?
	expect_equal(node.text(), "x--y")?

test "literal XML characters obey the same ranges as character references":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))

	for invalid in [
		"\u{0}", "\u{1}", "\u{8}", "\u{b}", "\u{c}", "\u{e}", "\u{1f}", "\u{fffe}",
		"\u{ffff}"
	]:
		expect_equal(parse("<a>{invalid}</a>"), malformed)?
		expect_equal(parse("<a v='{invalid}'/>"), malformed)?
		expect_equal(parse("<a><![CDATA[{invalid}]]></a>"), malformed)?
		expect_equal(parse("<!--{invalid}--><a/>"), malformed)?
		expect_equal(parse("<a/><?p {invalid}?>"), malformed)?
		expect_equal(parse("<!DOCTYPE a [<!ENTITY x '{invalid}'>]><a/>"), malformed)?

		code := invalid.scalar_values()[0]
		expect_equal(parse("<a>&#{code};</a>"), malformed)?

	for valid in [
		"\t", "\n", "\r", " ", "\u{7f}", "\u{85}", "\u{9f}", "\u{d7ff}", "\u{e000}",
		"\u{fffd}", "\u{10000}", "\u{10ffff}"
	]:
		expect_true(parse("<a>{valid}</a>").is_ok())?
		expect_true(parse("<a v='{valid}'/>").is_ok())?
		expect_true(parse("<a><![CDATA[{valid}]]></a>").is_ok())?
		expect_true(parse("<!--{valid}--><a/>").is_ok())?
		expect_true(parse("<a/><?p {valid}?>").is_ok())?
		expect_true(parse("<!DOCTYPE a [<!ENTITY x '{valid}'>]><a/>").is_ok())?

		code := valid.scalar_values()[0]
		expect_true(parse("<a>&#{code};</a>").is_ok())?

	expect_true(parse("\u{feff}<a/>").is_ok())?

test "CDATA terminators are forbidden only in literal character data":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))

	for text in ["]]>right", "left]]>", "left]]>right", "]]]>", "]]>"]:
		expect_equal(parse("<a>{text}</a>"), malformed)?
		expect_equal(parse("<a><b/>{text}</a>"), malformed)?

	for text in ["]]&gt;", "&#93;]>", "]&#93;>", "]]<b/>>", "]<!--c-->]>"]:
		expect_equal((parse("<a>{text}</a>")?).text(), "]]>")?

	attribute := parse("<a v=']]>'/>")?
	expect_equal(attribute.attribute("v").get(""), "]]>")?
	expect_equal((parse("<a><![CDATA[]]]]><![CDATA[>]]></a>")?).text(), "]]>")?
	for text in ["]]", "]>", "]"]:
		expect_equal((parse("<a>{text}</a>")?).text(), text)?

test "XML name starts follow every XML 1.0 range boundary":
	for code in [
		0x3a, 0x41, 0x5a, 0x5f, 0x61, 0x7a, 0xc0, 0xd6, 0xd8, 0xf6, 0xf8, 0x2ff, 0x370,
		0x37d, 0x37f, 0x1fff, 0x200c, 0x200d, 0x2070, 0x218f, 0x2c00, 0x2fef, 0x3001,
		0xd7ff, 0xf900, 0xfdcf, 0xfdf0, 0xfffd, 0x10000, 0xeffff
	]:
		scalar := from_scalars([code])?

		for name in [scalar.clone(), "a{scalar}"]:
			element := parse("<{name}></{name}>")?
			expect_equal(element.tag(), name)?

			attribute := parse("<a {name}='value'/>")?
			expect_equal(attribute.attribute(name).get(""), "value")?

test "XML continuation-only scalars cannot start a name":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))

	for code in [0x2d, 0x2e, 0x30, 0x39, 0xb7, 0x300, 0x36f, 0x203f, 0x2040]:
		scalar := from_scalars([code])?
		expect_equal(parse("<{scalar}/>"), malformed)?
		expect_equal(parse("<a {scalar}='value'/>"), malformed)?

		name := "a{scalar}"
		expect_equal((parse("<{name}></{name}>")?).tag(), name)?
		expect_equal((parse("<a {name}='value'/>")?).attribute(name).get(""), "value")?

test "XML names reject punctuation and excluded Unicode gaps":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))

	for code in [
		0x23, 0x24, 0x25, 0x2b, 0x40, 0x5b, 0x5c, 0x5d, 0x5e, 0x60, 0x7b, 0x7c, 0x7d,
		0x7e, 0x7f, 0xb6, 0xb8, 0xbf, 0xd7, 0xf7, 0x37e, 0x2000, 0x200b, 0x200e, 0x203e,
		0x2041, 0x206f, 0x2190, 0x2bff, 0x2ff0, 0x3000, 0xe000, 0xf8ff, 0xfdd0, 0xfdef,
		0xf0000, 0x10ffff
	]:
		scalar := from_scalars([code])?

		for name in [scalar.clone(), "a{scalar}"]:
			expect_equal(parse("<{name}/>"), malformed)?
			expect_equal(parse("<a {name}='value'/>"), malformed)?

test "line ends normalize to newline and attribute whitespace to spaces":
	doc := parse("<a k=\"x\ny\tz\r\nw\">t\r\nu\rv<![CDATA[c\r\nd]]></a>").get()
	expect_equal(doc.text(), "t\nu\nvc\nd")?
	expect_equal(doc.attribute("k").get(""), "x y z w")?

test "character references keep whitespace that normalization would change":
	doc := parse("<a k=\"x&#10;y&#9;z&#13;\">&#13;&#10;</a>").get()
	expect_equal(doc.attribute("k").get(""), "x\ny\tz\r")?
	expect_equal(doc.text(), "\r\n")?

test "carriage returns survive a stringify and parse round trip":
	source := XmlElement("a", [XmlAttribute("k", "p\rq\nr\ts")], [XmlText("t\r\nu")])
	text := stringify(source)
	expect_true(not text.contains("\r"))?

	back := parse(text).get()
	expect_equal(back.text(), "t\r\nu")?
	expect_equal(back.attribute("k").get(""), "p\rq\nr\ts")?

test "DOCTYPE skipping honors quoted spans and prolog placement":
	for accepted in [
		"<!DOCTYPE a SYSTEM \"a>b\"><a/>", "<!DOCTYPE a SYSTEM 'a>b'><a/>",
		"<!DOCTYPE a PUBLIC \"-//x//y\" \"u]>v\"><a/>",
		"<!DOCTYPE a [<!ENTITY x \"]>\">]><a/>",
		"<!DOCTYPE a [<!-- ]> --><!ELEMENT a EMPTY>]><a/>",
		"<!DOCTYPE a [<?p ]> ?><!ELEMENT a EMPTY>]><a/>", "<!DOCTYPE a [%e;]><a/>",
		"<?xml version=\"1.0\"?><!--c--><!DOCTYPE a><!--d--><a/>"
	]:
		expect_true(parse(accepted).is_ok())?
	for rejected in [
		"<a/><!DOCTYPE a>", "<!DOCTYPE a><!DOCTYPE a><a/>", "<!DOCTYPEa><a/>",
		"<!DOCTYPE><a/>", "<!DOCTYPE a SYSTEM><a/>",
		"<!DOCTYPE a [<!ENTITY x \"]>]><a/>", "<!DOCTYPE a [<!ELEMENT a EMPTY><a/>"
	]:
		expect_true(parse(rejected).is_error())?

test "DOCTYPE public identifiers accept only XML PubidChar scalars":
	malformed: XmlNode! := error(Error("XML: invalid data", kind: "EBADMSG"))

	for quote in ["\"", "'"]:
		for invalid in ["[", "]", "<", ">", "&", "\t", "é", "😀", "\"", "\\", "\{", "\}"]:
			expect_equal(invalid.length(), 1)?
			if invalid == quote: continue

			source := "<!DOCTYPE a PUBLIC {quote}{invalid}{quote} 'unused'><a/>"
			expect_equal(parse(source), malformed)?

		for valid in [
			"", "azAZ09", " \r\n-()+,./:=?;!*#@$_%", "-//W3C//DTD XHTML 1.0 Strict//EN"
		]:
			source := "<!DOCTYPE a PUBLIC {quote}{valid}{quote} 'unused'><a/>"
			expect_equal((parse(source)?).tag(), "a")?

	expect_true(parse("<!DOCTYPE a PUBLIC \"apostrophe's\" 'unused'><a/>").is_ok())?

	// A system literal has a different grammar; brackets and Unicode stay legal there.
	expect_true(parse("<!DOCTYPE a SYSTEM 'é[<&>😀'><a/>").is_ok())?
	expect_true(parse("<!DOCTYPE a PUBLIC 'valid' 'é[<&>😀'><a/>").is_ok())?

test "elements with many attributes keep their order and reject duplicates at any position":
	var text = "<root"
	for i in 0..40:
		text += " a{i}=\"{i}\""

	doc := parse(text + "/>").get()
	expect_equal(doc.attribute("a0").get(""), "0")?
	expect_equal(doc.attribute("a39").get(""), "39")?
	expect_equal(doc.attribute("a15").get(""), "15")?
	expect_equal(doc.attribute("a16").get(""), "16")?

	// The 16th attribute is the first one checked through the set, and its list-scanned
	// predecessors count.
	expect_true(parse(text + " a0=\"x\"/>").is_error())?
	expect_true(parse(text + " a16=\"x\"/>").is_error())?
	expect_true(parse(text + " a39=\"x\"/>").is_error())?
	expect_true(parse(text + " a40=\"x\"/>").is_ok())?
	expect_true(parse("<root a=\"1\" b=\"2\" a=\"3\"/>").is_error())?

test "delimiter scans preserve empty spans Unicode and partial terminators":
	expect_equal(parse("<a><![CDATA[]]></a>").get().text(), "")?
	expect_equal(parse("<?p?><a k=''/>").get().attribute("k").get(), "")?

	text := "é日]]x?y".repeat(1000).get()
	doc := parse("<a><![CDATA[{text}]]></a>").get()
	expect_equal(doc.text(), text)?

	attribute := parse("<a k='{text}'/>").get()
	expect_equal(attribute.attribute("k").get(), text)?
	for source in ["<a><!--x--", "<a><![CDATA[]]", "<a k='x", "<?p x?"]:
		expect_equal(parse(source).err().kind, "EBADMSG")?
