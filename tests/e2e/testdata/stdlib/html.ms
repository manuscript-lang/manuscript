import {escape, parse, HtmlNode, HtmlAttribute, HtmlLimits, HtmlError} from "@std/html.ms"
import panic from "@std/faults.ms"

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
    if escape("<&>\"'") != "&lt;&amp;&gt;&#34;&#39;": return panic("HTML entities")
    if escape("é🙂") != "é🙂": return panic("Unicode changed")
    if escape("") != "": return panic("empty HTML")

test "HTML parses nested elements attributes entities and comments":
    let doc = try parse(
        "<DIV id='main' title='A &amp; B' hidden>Hello <b>é🙂</b> &lt;world&gt;<!--note--><br></DIV>"
    )
    let div = body_nodes(doc).at(0).get()

    match div:
        Element(tag, namespace, attributes, items):
            if tag != "div" or namespace != "": return panic("HTML name normalization")
            if (
                attributes != [
                    HtmlAttribute("id", "", "main"),
                    HtmlAttribute("title", "", "A & B"),
                    HtmlAttribute("hidden", "", "")
                ]
            ): return panic("HTML attributes")
            if (
                items.at(0).get() != HtmlNode.Text("Hello ")
                or items.at(2).get() != HtmlNode.Text(" <world>")
            ): return panic("HTML text ordering or entities")
            if items.at(3).get() != HtmlNode.Comment("note"): return panic(
                "HTML comment"
            )
            if (
                items.at(4).get() != HtmlNode.Element(
                    tag: "br",
                    namespace: "",
                    attributes: [],
                    children: []
                )
            ): return panic("void element")
        _: return panic("expected element")

    if text_content(doc) != "Hello é🙂 <world>": return panic("tree traversal")

test "HTML recovers unclosed tags and inserts document and table structure":
    let doc = try parse("<ul><li>one<li>two</ul><table><tr><td>cell")
    let nodes = body_nodes(doc)
    let entries = children(nodes.at(0).get())
    if (
        entries.length() != 2
        or text_content(entries.at(0).get()) != "one"
        or text_content((entries.at(1).get())) != "two"
    ): return panic("implicit li closure")

    match children(nodes.at(1).get()).at(0).get():
        Element(tag, _, _, _):
            if tag != "tbody": return panic("implicit tbody")
        _: return panic("expected tbody")

    if text_content(nodes.at(1).get()) != "cell": return panic("unclosed table")

    let empty = try parse("")
    if children(children(empty).at(0).get()).length() != 2: return panic(
        "implicit head and body"
    )

test "HTML preserves doctypes foreign namespaces and raw script text":
    let doc = try parse(
        "<!DOCTYPE html PUBLIC 'public' 'system'><!--before--><svg><a xlink:href='#icon'/></svg><script>if (a < b) x = '&amp;';</script>"
    )
    let nodes = children(doc)
    if (
        nodes.at(0).get() != HtmlNode.Doctype(
            name: "html",
            public_id: "public",
            system_id: "system"
        )
    ): return panic("doctype identifiers")
    if nodes.at(1).get() != HtmlNode.Comment("before"): return panic("document comment")

    let body = children(children(nodes.at(2).get()).at(1).get())

    let svg_items = match body.at(0).get():
        Element(tag, namespace, _, items):
            if tag != "svg" or namespace != "svg": return panic("SVG namespace")
            items
        _: return panic("expected SVG")

    match svg_items.at(0).get():
        Element(_, child_namespace, attributes, _):
            if (
                child_namespace != "svg"
                or attributes.at(0).get() != HtmlAttribute(
                    "href",
                    "xlink",
                    "#icon"
                )
            ): return panic("namespaced attribute")
        _: return panic("expected SVG anchor")

    if text_content(body.at(1).get()) != "if (a < b) x = '&amp;';": return panic(
        "script raw text"
    )

test "HTML honors optional byte depth and node limits":
    let empty = try parse("")
    if ((try parse("", HtmlLimits(0, 2, 4))) != empty): return panic(
        "exact HTML limits"
    )
    if ((try parse("é", HtmlLimits())) != (try parse("é"))): return panic(
        "omitted HTML limits"
    )

    let limited: Result[HtmlNode, HtmlError] = error(HtmlError.LimitExceeded)
    if (parse("é", HtmlLimits(1)) != limited): return panic("UTF-8 byte limit")
    if (parse("", HtmlLimits(max_depth: 1)) != limited): return panic(
        "implicit node depth limit"
    )
    if (parse("", HtmlLimits(max_nodes: 3)) != limited): return panic(
        "implicit node count limit"
    )

    let invalid: Result[HtmlNode, HtmlError] = error(HtmlError.InvalidInput)
    if (parse("", HtmlLimits(max_nodes: -1)) != invalid): return panic(
        "negative HTML limit"
    )
    if HtmlError.InvalidData.message() == "": return panic("HTML error diagnostic")
