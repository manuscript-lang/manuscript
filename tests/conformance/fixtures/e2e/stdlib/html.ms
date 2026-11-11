// conform: tags=testing,tier-io
// conform: phase=test
import (
	HtmlAttribute,
	HtmlNode,
	HtmlOptions,
	escape,
	parse,
	unescape from "@std/data/html.ms",
	expect_equal, expect_false, expect_not_equal, fail from "@std/test/test.ms",
	monotonic from "@std/time.ms",
)

fn children(node: HtmlNode) List[HtmlNode]:
	match node:
		Document(items): return items.clone()
		Element(_, _, _, items): return items.clone()
		_: return []

fn text_content(node: HtmlNode) String:
	match node:
		Text(text): return text.clone()
		Document(items):
			var text = ""
			for item in items: text = "{text}{text_content(item)}"
			return text
		Element(_, _, _, items):
			var text = ""
			for item in items: text = "{text}{text_content(item)}"
			return text
		_: return ""

fn body_nodes(node: HtmlNode) List[HtmlNode]:
	html := children(node).get(0).clone()
	return children(children(html).get(1))

test "HTML escaping preserves Unicode and escapes all markup characters":
	expect_equal(escape("<&>\"'"), "&lt;&amp;&gt;&#34;&#39;")?
	expect_equal(escape("é🙂"), "é🙂")?
	expect_equal(escape(""), "")?

test "HTML parses nested elements attributes entities and comments":
	doc := parse(
		"<DIV id='main' title='A &amp; B' hidden>Hello <b>é🙂</b> &lt;world&gt;<!--note--><br></DIV>"
	)?
	div := body_nodes(doc.clone()).get(0).clone()

	match div:
		Element(tag, namespace, attributes, items):
			expect_false(tag != "div" or namespace != "")?
			expect_false(
				(
					attributes != [
						HtmlAttribute("id", "", "main"),
						HtmlAttribute("title", "", "A & B"),
						HtmlAttribute("hidden", "", ""),
					]
				)
			)?
			expect_false(
				(
					items.get(0) != HtmlNode.Text("Hello ")
					or items.get(2) != HtmlNode.Text(" <world>")
				)
			)?
			expect_equal(items.get(3), HtmlNode.Comment("note"))?
			expect_false(
				(
					items.get(4) != HtmlNode.Element(
						tag: "br",
						namespace: "",
						attributes: [],
						children: [],
					)
				)
			)?
		_: return fail("expected element")

	expect_equal(text_content(doc), "Hello é🙂 <world>")?

test "HTML recovers unclosed tags and inserts document and table structure":
	doc := parse("<ul><li>one<li>two</ul><table><tr><td>cell")?
	nodes := body_nodes(doc)
	entries := children(nodes.get(0).clone())
	expect_false(
		(
			entries.length() != 2
			or text_content(entries.get(0).clone()) != "one"
			or text_content(entries.get(1).clone()) != "two"
		)
	)?

	match children(nodes.get(1).clone()).get(0).clone():
		Element(tag, _, _, _):
			expect_equal(tag, "tbody")?
		_: return fail("expected tbody")

	expect_equal(text_content(nodes.get(1).clone()), "cell")?

	empty := parse("")?
	expect_equal(children(children(empty).get(0)).length(), 2)?

test "HTML preserves doctypes foreign namespaces and raw script text":
	doc := parse(
		"<!DOCTYPE html PUBLIC 'public' 'system'><!--before--><svg><a xlink:href='#icon'/></svg><script>if (a < b) x = '&amp;';</script>"
	)?
	nodes := children(doc)
	expect_false(
		(
			nodes.get(0) != HtmlNode.Doctype(
				name: "html",
				public_id: "public",
				system_id: "system",
			)
		)
	)?
	expect_equal(nodes.get(1), HtmlNode.Comment("before"))?

	body := children(children(nodes.get(2).clone()).get(1).clone())

	svg_items := match body.get(0):
		Element(tag, namespace, _, items):
			expect_false(tag != "svg" or namespace != "svg")?
			items.clone()
		_: return fail("expected SVG")

	match svg_items.get(0):
		Element(_, child_namespace, attributes, _):
			expect_false(
				(
					child_namespace != "svg"
					or attributes.get(0) != HtmlAttribute(
						"href",
						"xlink",
						"#icon",
					)
				)
			)?
		_: return fail("expected SVG anchor")

	expect_equal(text_content(body.get(1).clone()), "if (a < b) x = '&amp;';")?

test "HTML honors optional byte depth and node limits":
	empty := parse("")?
	expect_equal(
		(parse("", HtmlOptions(max_bytes: 0, max_depth: 2, max_nodes: 4))?),
		empty,
	)?
	expect_equal((parse("é", HtmlOptions())?), (parse("é")?))?

	limited: HtmlNode! := error(Error("HTML: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(parse("é", HtmlOptions(max_bytes: 1)), limited)?
	expect_equal(parse("", HtmlOptions(max_depth: 1)), limited)?
	expect_equal(parse("", HtmlOptions(max_nodes: 3)), limited)?

	invalid: HtmlNode! := error(Error("HTML: invalid input", kind: "EINVAL"))
	expect_equal(parse("", HtmlOptions(max_nodes: -1)), invalid)?
	expect_not_equal(Error("HTML: invalid data", kind: "EBADMSG").message, "")?

test "HTML depth limit stops deeply nested input without quadratic work":
	// 60,000 open divs take tens of seconds when the parser only checks depth
	// afterwards.
	nested := "<div>".repeat(60000).get()
	started := monotonic()
	limited: HtmlNode! := error(Error("HTML: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(parse(nested, HtmlOptions(max_depth: 100)), limited)?

	elapsed := monotonic().difference(started).to_milliseconds()
	if elapsed > 5000: return fail("depth limit took {elapsed} ms")

test "HTML parse applies default limits and none lifts them":
	nested := "<div>".repeat(20000).get()
	limited: HtmlNode! := error(Error("HTML: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(parse(nested), limited)?

	lifted := parse(nested, HtmlOptions(max_depth: none, max_nodes: none))
	expect_false(lifted.is_error())?

test "unescape maps overflowing numeric references to U+FFFD instead of wrapping":
	expect_equal(unescape("&#4294967361;"), "\u{fffd}")?
	expect_equal(unescape("&#x100000041;"), "\u{fffd}")?
	expect_equal(unescape("&#99999999999999999999999"), "\u{fffd}")?
	expect_equal(unescape("&#1114111;&#1114112;"), "\u{10ffff}\u{fffd}")?

test "unescape decodes one-digit numeric references without a semicolon":
	expect_equal(unescape("&#9F"), "\u{9}F")?
	expect_equal(unescape("&#1"), "\u{1}")?
	expect_equal(unescape("&#0"), "\u{fffd}")?
	expect_equal(unescape("&#x4"), "\u{4}")?
	expect_equal(unescape("&#65x"), "Ax")?

test "unescape keeps references without digits literal":
	expect_equal(unescape("&#"), "&#")?
	expect_equal(unescape("&#;"), "&#;")?
	expect_equal(unescape("&#x"), "&#x")?
	expect_equal(unescape("&#xg"), "&#xg")?
	expect_equal(unescape("&#x;"), "&#x;")?

test "unescape maps the HTML5 nGt and nLt references to two scalars":
	expect_equal(unescape("&nGt;"), "\u{226b}\u{20d2}")?
	expect_equal(unescape("&nLt;"), "\u{226a}\u{20d2}")?
	expect_equal(unescape("&nGtv;"), "\u{226b}\u{338}")?
