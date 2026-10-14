import {
    parse,
    stringify,
    HtmlNode,
    HtmlLimits,
    HtmlError
} from "@std/html.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn first_document_node(value: HtmlNode) -> HtmlNode:
    match value:
        HtmlNode.Document(children): return children.first().unwrap()
        _: return panic("expected parsed HTML document")

test "HTML stringify rejects terminating doctype identifiers and retains legal text":
    let invalid: Result[String, HtmlError] = error(HtmlError.InvalidData)

    for identifier in ["a>b", "a\"b>c", "a'b>c", "both'\"quotes"]:
        if stringify(HtmlNode.Doctype("html", identifier, "")) != invalid: return panic(
            "invalid public doctype identifier"
        )
        if stringify(HtmlNode.Doctype("html", "", identifier)) != invalid: return panic(
            "invalid system doctype identifier"
        )

    for identifier in ["a'b", "a\"b", "a&b", "a<b", "é🙂", " spaced\tidentifier "]:
        let declarations = [
            HtmlNode.Doctype("html", identifier, ""),
            HtmlNode.Doctype("html", "", identifier),
            HtmlNode.Doctype("html", identifier, identifier)
        ]

        for declaration in declarations:
            let decoded = value(
                parse(
                    value(stringify(declaration))
                )
            )
            if first_document_node(decoded) != declaration: return panic(
                "legal doctype identifier changed on round trip"
            )

    let references = value(
        stringify(HtmlNode.Doctype("html", "a&lt;b", "a&lt;b"))
    )
    if references != "<!DOCTYPE html PUBLIC \"a&lt;b\" \"a&lt;b\">": return panic(
        "doctype reference spelling changed during rendering"
    )
    if (
        first_document_node(
            value(parse(references))
        ) != HtmlNode.Doctype(
            "html",
            "a<b",
            "a<b"
        )
    ): return panic("doctype native parser reference normalization")

test "HTML stringify round trips normalized trees and preserves raw text":
    let tree = value(
        parse(
            "<!DOCTYPE html PUBLIC 'pub' 'sys'><!--note--><svg><a xlink:href='#icon'>é🙂 &amp; text</a></svg><script>if (a < b) x = '&amp;';</script><pre>\nline</pre>"
        )
    )
    let encoded = value(stringify(tree))
    if value(parse(encoded)) != tree: return panic("HTML round trip")

    let duplicates = value(parse("<p data-x='first' data-x='second'>text</p>"))
    if value(
        parse(
            value(stringify(duplicates))
        )
    ) != duplicates: return panic(
        "HTML duplicate attributes"
    )

    let shared: List[HtmlNode] = [HtmlNode.Text("é & <")]
    let child = HtmlNode.Element(
        tag: "b",
        namespace: "",
        attributes: [],
        children: shared
    )
    let root = HtmlNode.Document([child, child])
    if value(stringify(root)) != "<b>é &amp; &lt;</b><b>é &amp; &lt;</b>": return panic(
        "HTML shared subtree"
    )
    if shared != [HtmlNode.Text("é & <")]: return panic("HTML input mutated")

test "HTML stringify reports cycles invalid structures and optional budgets":
    let children: List[HtmlNode] = []
    let cycle = HtmlNode.Element(
        tag: "div",
        namespace: "",
        attributes: [],
        children: children
    )
    children.append(cycle)
    let invalid: Result[String, HtmlError] = error(HtmlError.InvalidData)
    let limited: Result[String, HtmlError] = error(HtmlError.LimitExceeded)
    let bad_limits: Result[String, HtmlError] = error(HtmlError.InvalidInput)
    if stringify(cycle) != invalid: return panic("HTML cycle")
    if (
        stringify(
            HtmlNode.Element(
                tag: "x bad='value'",
                namespace: "",
                attributes: [],
                children: []
            )
        ) != invalid
    ): return panic("HTML invalid name")
    if (
        stringify(
            HtmlNode.Element(
                tag: "br",
                namespace: "",
                attributes: [],
                children: [HtmlNode.Text("child")]
            )
        ) != invalid
    ): return panic("HTML void children")

    let root = HtmlNode.Document([HtmlNode.Text("é &")])
    if stringify(
        root,
        HtmlLimits(max_bytes: 7)
    ) != limited: return panic("HTML output byte limit")
    if stringify(
        root,
        HtmlLimits(max_depth: 0)
    ) != limited: return panic("HTML root-zero depth limit")
    if stringify(
        root,
        HtmlLimits(max_nodes: 1)
    ) != limited: return panic("HTML node count")
    if stringify(
        root,
        HtmlLimits(max_nodes: -1)
    ) != bad_limits: return panic("HTML negative limit")
    if (
        value(
            stringify(
                root,
                HtmlLimits(max_bytes: 8, max_depth: 1, max_nodes: 2)
            )
        ) != "é &amp;"
    ): return panic("HTML exact limits")
