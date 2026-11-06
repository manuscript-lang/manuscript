import (
    HtmlLimits,
    msstd_html_escape,
    msstd_html_unescape,
    msstd_html_parse,
    msstd_html_root,
    msstd_html_kind,
    msstd_html_data,
    msstd_html_namespace,
    msstd_html_doctype_id,
    msstd_html_first_child,
    msstd_html_next_sibling,
    msstd_html_attr_count,
    msstd_html_attr
) from "@std/internal/html.ms"

// Bounds for HTML input bytes, tree depth, and node count.
// Fields set to none add no budget. The defaults are depth 10,000 and 1,000,000 nodes.
export type HtmlOptions:
    // Maximum UTF-8 input bytes before parsing; none adds no input-size budget.
    max_bytes: Int? = none
    // Maximum normalized node depth; the document is depth zero and direct children depth one.
    max_depth: Int? = 10000
    // Maximum returned nodes, including document/text/comment/doctype and implied element nodes.
    max_nodes: Int? = 1000000

// An HTML attribute, including its namespace and decoded value.
export type HtmlAttribute:
    // Local attribute name after native HTML parsing and normalization.
    name: String
    // Attribute namespace prefix, or empty text for an unqualified attribute.
    namespace: String
    // Decoded attribute contents, with character references resolved.
    value: String

// A parsed HTML document tree with document, element, text, comment, and doctype nodes.
export enum HtmlNode:
    // Root document node, including any elements implied by HTML tree normalization.
    Document(
        // Direct child nodes in normalized document order.
        children: List[HtmlNode]
    )
    // An element with normalized attributes and its ordered child nodes.
    Element(
        // Local element tag name produced by the HTML parser.
        tag: String,
        // Element namespace, such as svg/math, or empty text for ordinary HTML.
        namespace: String,
        // Attributes in parser order, with decoded values and namespace information.
        attributes: List[HtmlAttribute],
        // Direct child nodes in normalized tree order; mutable list storage is retained.
        children: List[HtmlNode]
    )
    // Text node contents after HTML entity decoding and tree normalization.
    Text(
        // Unicode text belonging to this node, without surrounding markup.
        text: String
    )
    // An HTML comment retained as a node rather than element text.
    Comment(
        // Comment contents without the opening and closing comment delimiters.
        text: String
    )
    // A document-type declaration retained from the parsed HTML.
    Doctype(
        // Doctype name supplied by the native HTML parser.
        name: String,
        // Public identifier, or empty text when no public identifier is present.
        public_id: String,
        // System identifier, or empty text when no system identifier is present.
        system_id: String
    )

// Escapes text for insertion into an HTML text or quoted attribute context.
export fn escape(text: String) String:
    return msstd_html_escape(text)

// Decodes HTML5 named and numeric character references in text context, once.
// Recognized references can omit semicolons; unrecognized text remains literal.
// Does not parse markup or normalize text; invalid numeric scalars become U+FFFD.
export fn unescape(text: String) String:
    return msstd_html_unescape(text)

// A parse tree owned by the runtime; node ids are valid only for the tree that issued them, and -1 is no node.
export extern type HtmlTree

// Parses HTML into a normalized tree and applies the resource limits in `options`.
export fn parse(text: String, options: HtmlOptions = HtmlOptions()) HtmlNode!:
    let limits = HtmlLimits(
        max_bytes: options.max_bytes, max_depth: options.max_depth,
        max_nodes: options.max_nodes
    )
    let tree = try msstd_html_parse(text, limits)
    return ok(node(tree, msstd_html_root(tree)))

// Copies the node `id` of `tree`, and everything under it, into an `HtmlNode`.
fn node(tree: HtmlTree, id: Int) HtmlNode:
    let kind = msstd_html_kind(tree, id)
    if kind == 1:
        return HtmlNode.Element(
            msstd_html_data(tree, id), msstd_html_namespace(tree, id),
            attributes(tree, id), children(tree, id)
        )
    if kind == 2:
        return HtmlNode.Text(msstd_html_data(tree, id))
    if kind == 3:
        return HtmlNode.Comment(msstd_html_data(tree, id))
    if kind == 4:
        return HtmlNode.Doctype(
            msstd_html_data(tree, id), msstd_html_doctype_id(tree, id, 0),
            msstd_html_doctype_id(tree, id, 1)
        )

    return HtmlNode.Document(children(tree, id))

fn children(tree: HtmlTree, id: Int) List[HtmlNode]:
    var out: List[HtmlNode] = []
    var at = msstd_html_first_child(tree, id)

    while at >= 0:
        out.append(node(tree, at))
        at = msstd_html_next_sibling(tree, at)

    return out

fn attributes(tree: HtmlTree, id: Int) List[HtmlAttribute]:
    var out: List[HtmlAttribute] = []
    for i in 0..msstd_html_attr_count(tree, id):
        out.append(
            HtmlAttribute(
                name: msstd_html_attr(tree, id, i, 0),
                namespace: msstd_html_attr(tree, id, i, 1),
                value: msstd_html_attr(tree, id, i, 2)
            )
        )
    return out
