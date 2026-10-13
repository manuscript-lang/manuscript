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
