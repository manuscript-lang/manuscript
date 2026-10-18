import {expect_equal, expect_false, expect_not_equal, fail} from "@std/testing.ms"
import {escape, parse, HtmlNode, HtmlAttribute, HtmlLimits, HtmlError} from "@std/html.ms"

fn children(node: HtmlNode) List[HtmlNode]:
    match node:
        Document(items): return items
        Element(_, _, _, items): return items
        _: return []

fn text_content(node: HtmlNode) String:
    match node:
        Text(text): return text
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
    let html = children(node).at(0).get()
    return children(children(html).at(1).get())

test "HTML escaping preserves Unicode and escapes all markup characters":
    try expect_equal(escape("<&>\"'"), "&lt;&amp;&gt;&#34;&#39;")
    try expect_equal(escape("é🙂"), "é🙂")
    try expect_equal(escape(""), "")

test "HTML parses nested elements attributes entities and comments":
    let doc = try parse(
        "<DIV id='main' title='A &amp; B' hidden>Hello <b>é🙂</b> &lt;world&gt;<!--note--><br></DIV>"
    )
    let div = body_nodes(doc).at(0).get()

    match div:
        Element(tag, namespace, attributes, items):
            try expect_false(tag != "div" or namespace != "")
            try expect_false(
                (
                    attributes != [
                        HtmlAttribute("id", "", "main"),
                        HtmlAttribute("title", "", "A & B"),
                        HtmlAttribute("hidden", "", "")
                    ]
                )
            )
            try expect_false(
                (
                    items.at(0).get() != HtmlNode.Text("Hello ")
                    or items.at(2).get() != HtmlNode.Text(
                        " <world>"
                    )
                )
            )
            try expect_equal(items.at(3).get(), HtmlNode.Comment("note"))
            try expect_false(
                (
                    items.at(4).get() != HtmlNode.Element(
                        tag: "br",
                        namespace: "",
                        attributes: [],
                        children: []
                    )
                )
            )
        _: return fail("expected element")

    try expect_equal(text_content(doc), "Hello é🙂 <world>")

test "HTML recovers unclosed tags and inserts document and table structure":
    let doc = try parse("<ul><li>one<li>two</ul><table><tr><td>cell")
    let nodes = body_nodes(doc)
    let entries = children(nodes.at(0).get())
    try expect_false(
        (
            entries.length() != 2
            or text_content(entries.at(0).get()) != "one"
            or text_content((entries.at(1).get())) != "two"
        )
    )

    match children(nodes.at(1).get()).at(0).get():
        Element(tag, _, _, _):
            try expect_equal(tag, "tbody")
        _: return fail("expected tbody")

    try expect_equal(text_content(nodes.at(1).get()), "cell")
    let empty = try parse("")
    try expect_equal(children(children(empty).at(0).get()).length(), 2)

test "HTML preserves doctypes foreign namespaces and raw script text":
    let doc = try parse(
        "<!DOCTYPE html PUBLIC 'public' 'system'><!--before--><svg><a xlink:href='#icon'/></svg><script>if (a < b) x = '&amp;';</script>"
    )
    let nodes = children(doc)
    try expect_false(
        (
            nodes.at(0).get() != HtmlNode.Doctype(
                name: "html",
                public_id: "public",
                system_id: "system"
            )
        )
    )
    try expect_equal(nodes.at(1).get(), HtmlNode.Comment("before"))
    let body = children(children(nodes.at(2).get()).at(1).get())

    let svg_items = match body.at(0).get():
        Element(tag, namespace, _, items):
            try expect_false(tag != "svg" or namespace != "svg")
            items
        _: return fail("expected SVG")

    match svg_items.at(0).get():
        Element(_, child_namespace, attributes, _):
            try expect_false(
                (
                    child_namespace != "svg"
                    or attributes.at(0).get() != HtmlAttribute(
                        "href",
                        "xlink",
                        "#icon"
                    )
                )
            )
        _: return fail("expected SVG anchor")

    try expect_equal(text_content(body.at(1).get()), "if (a < b) x = '&amp;';")

test "HTML honors optional byte depth and node limits":
    let empty = try parse("")
    try expect_equal((try parse("", HtmlLimits(0, 2, 4))), empty)
    try expect_equal((try parse("é", HtmlLimits())), (try parse("é")))
    let limited: Result[HtmlNode, HtmlError] = error(HtmlError.LimitExceeded)
    try expect_equal(parse("é", HtmlLimits(1)), limited)
    try expect_equal(parse("", HtmlLimits(max_depth: 1)), limited)
    try expect_equal(parse("", HtmlLimits(max_nodes: 3)), limited)
    let invalid: Result[HtmlNode, HtmlError] = error(HtmlError.InvalidInput)
    try expect_equal(parse("", HtmlLimits(max_nodes: -1)), invalid)
    try expect_not_equal(HtmlError.InvalidData.message(), "")
