import (
    msstd_html_escape,
    msstd_html_unescape,
    msstd_html_parse
) from "@std/internal/html.ms"

# Optional bounds for HTML input bytes, tree depth, and node count.
# Fields left none add no budget. Calling `parse` without any limits applies depth 10,000 and 1,000,000 nodes; pass an `HtmlLimits` to change that.
export type HtmlLimits:
    # Maximum UTF-8 input bytes before parsing; none adds no input-size budget.
    max_bytes: Int?
    # Maximum normalized node depth; the document is depth zero and direct children depth one.
    max_depth: Int?
    # Maximum returned nodes, including document/text/comment/doctype and implied element nodes.
    max_nodes: Int?

# An HTML attribute, including its namespace and decoded value.
export type HtmlAttribute:
    # Local attribute name after native HTML parsing and normalization.
    name: String
    # Attribute namespace prefix, or empty text for an unqualified attribute.
    namespace: String
    # Decoded attribute contents, with character references resolved.
    value: String

# A parsed HTML document tree with document, element, text, comment, and doctype nodes.
export type HtmlNode:
    # Root document node, including any elements implied by HTML tree normalization.
    case Document(
        # Direct child nodes in normalized document order.
        children: List[HtmlNode]
    )
    # An element with normalized attributes and its ordered child nodes.
    case Element(
        # Local element tag name produced by the HTML parser.
        tag: String,
        # Element namespace, such as svg/math, or empty text for ordinary HTML.
        namespace: String,
        # Attributes in parser order, with decoded values and namespace information.
        attributes: List[HtmlAttribute],
        # Direct child nodes in normalized tree order; mutable list storage is retained.
        children: List[HtmlNode]
    )
    # Text node contents after HTML entity decoding and tree normalization.
    case Text(
        # Unicode text belonging to this node, without surrounding markup.
        text: String
    )
    # An HTML comment retained as a node rather than element text.
    case Comment(
        # Comment contents without the opening and closing comment delimiters.
        text: String
    )
    # A document-type declaration retained from the parsed HTML.
    case Doctype(
        # Doctype name supplied by the native HTML parser.
        name: String,
        # Public identifier, or empty text when no public identifier is present.
        public_id: String,
        # System identifier, or empty text when no system identifier is present.
        system_id: String
    )

# Escapes text for insertion into an HTML text or quoted attribute context.
export fn escape(text: String) String:
    return msstd_html_escape(text)

# Decodes HTML5 named and numeric character references in text context, once.
# Recognized references can omit semicolons; unrecognized text remains literal.
# Does not parse markup or normalize text; invalid numeric scalars become U+FFFD.
export fn unescape(text: String) String:
    return msstd_html_unescape(text)

# Parses HTML into a normalized tree and applies the supplied resource limits.
export fn parse(text: String, limits: HtmlLimits?) HtmlNode!:
    return msstd_html_parse(text, limits)
