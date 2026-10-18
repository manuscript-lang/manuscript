import {expect_equal, expect_false, expect_not_equal, expect_ok, fail} from "@std/testing.ms"
import {escape, parse, HtmlNode, HtmlAttribute, HtmlLimits, HtmlError} from "@std/html.ms"

fn children(node: HtmlNode) -> List[HtmlNode]:
    match node:
        Document(items): return items
        Element(_, _, _, items): return items
        _: return []

fn text_content(node: HtmlNode) -> String:
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

fn body_nodes(node: HtmlNode) -> List[HtmlNode]:
    let html = children(node).at(0).unwrap()
    return children(children(html).at(1).unwrap())

test "HTML escaping preserves Unicode and escapes all markup characters":
    escape("<&>\"'") | try expect_equal(expected: "&lt;&amp;&gt;&#34;&#39;")
    escape("é🙂") | try expect_equal(expected: "é🙂")
    escape("") | try expect_equal(expected: "")

test "HTML parses nested elements attributes entities and comments":
    let doc = (
        parse(
            text: "<DIV id='main' title='A &amp; B' hidden>Hello <b>é🙂</b> &lt;world&gt;<!--note--><br></DIV>"
        ) | try expect_ok
    )
    let div = body_nodes(doc).at(0).unwrap()

    match div:
        Element(tag, namespace, attributes, items):
            (tag != "div" or namespace != "") | try expect_false
            try expect_false(
                (
                    attributes != [
                        HtmlAttribute(
                            name: "id",
                            namespace: "",
                            value: "main"
                        ),
                        HtmlAttribute(
                            name: "title",
                            namespace: "",
                            value: "A & B"
                        ),
                        HtmlAttribute(
                            name: "hidden",
                            namespace: "",
                            value: ""
                        )
                    ]
                )
            )
            try expect_false(
                (
                    items.at(0).unwrap() != HtmlNode.Text("Hello ")
                    or items.at(2).unwrap() != HtmlNode.Text(
                        " <world>"
                    )
                )
            )
            items.at(3).unwrap() | try expect_equal(expected: HtmlNode.Comment("note"))
            try expect_false(
                (
                    items.at(4).unwrap() != HtmlNode.Element(
                        tag: "br",
                        namespace: "",
                        attributes: [],
                        children: []
                    )
                )
            )
        _: return fail("expected element")

    text_content(doc) | try expect_equal(expected: "Hello é🙂 <world>")

test "HTML recovers unclosed tags and inserts document and table structure":
    let doc = (
        parse(
            text: "<ul><li>one<li>two</ul><table><tr><td>cell"
        ) | try expect_ok
    )
    let nodes = body_nodes(doc)
    let entries = children(nodes.at(0).unwrap())
    try expect_false(
        (
            entries.length() != 2
            or text_content(entries.at(0).unwrap()) != "one"
            or text_content((entries.at(1).unwrap())) != "two"
        )
    )

    match children(nodes.at(1).unwrap()).at(0).unwrap():
        Element(tag, _, _, _):
            try expect_equal(tag, "tbody")
        _: return fail("expected tbody")

    text_content(nodes.at(1).unwrap()) | try expect_equal(expected: "cell")
    let empty = (parse(text: "") | try expect_ok)
    children(children(empty).at(0).unwrap()).length() | try expect_equal(expected: 2)

test "HTML preserves doctypes foreign namespaces and raw script text":
    let doc = (
        parse(
            text: "<!DOCTYPE html PUBLIC 'public' 'system'><!--before--><svg><a xlink:href='#icon'/></svg><script>if (a < b) x = '&amp;';</script>"
        ) | try expect_ok
    )
    let nodes = children(doc)
    try expect_false(
        (
            nodes.at(0).unwrap() != HtmlNode.Doctype(
                name: "html",
                public_id: "public",
                system_id: "system"
            )
        )
    )
    nodes.at(1).unwrap() | try expect_equal(expected: HtmlNode.Comment("before"))
    let body = children(children(nodes.at(2).unwrap()).at(1).unwrap())

    let svg_items = match body.at(0).unwrap():
        Element(tag, namespace, _, items):
            (tag != "svg" or namespace != "svg") | try expect_false
            items
        _: return fail("expected SVG")

    match svg_items.at(0).unwrap():
        Element(_, child_namespace, attributes, _):
            try expect_false(
                (
                    child_namespace != "svg"
                    or attributes.at(0).unwrap() != HtmlAttribute(
                        name: "href",
                        namespace: "xlink",
                        value: "#icon"
                    )
                )
            )
        _: return fail("expected SVG anchor")

    text_content(body.at(1).unwrap()) | try expect_equal(
        expected: "if (a < b) x = '&amp;';"
    )

test "HTML honors optional byte depth and node limits":
    let empty = (parse(text: "") | try expect_ok)
    try expect_false(
        (
            (
                parse(
                    text: "",
                    limits: HtmlLimits(
                        max_bytes: 0,
                        max_depth: 2,
                        max_nodes: 4
                    )
                ) | try expect_ok
            ) != empty
        )
    )
    parse(text: "é", limits: HtmlLimits()) | try expect_ok | try expect_equal(
        expected: (parse(text: "é") | try expect_ok)
    )
    let limited: Result[HtmlNode, HtmlError] = error(HtmlError.LimitExceeded)
    parse(text: "é", limits: HtmlLimits(max_bytes: 1)) | try expect_equal(
        expected: limited
    )
    parse(text: "", limits: HtmlLimits(max_depth: 1)) | try expect_equal(
        expected: limited
    )
    parse(text: "", limits: HtmlLimits(max_nodes: 3)) | try expect_equal(
        expected: limited
    )
    let invalid: Result[HtmlNode, HtmlError] = error(HtmlError.InvalidInput)
    parse(text: "", limits: HtmlLimits(max_nodes: -1)) | try expect_equal(
        expected: invalid
    )
    HtmlError.InvalidData.message() | try expect_not_equal(expected: "")
