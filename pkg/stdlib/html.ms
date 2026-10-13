# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned for malformed HTML or parser resource limits.
export type HtmlError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# Optional bounds for HTML input bytes, tree depth, and node count.
export type HtmlLimits:
    max_bytes: Optional[Int] = none
    max_depth: Optional[Int] = none
    max_nodes: Optional[Int] = none

# An HTML attribute, including its namespace and decoded value.
export type HtmlAttribute:
    name: String
    namespace: String
    value: String

# A parsed HTML document tree with document, element, text, comment, and doctype nodes.
export type HtmlNode:
    case Document(children: List[HtmlNode])
    case Element(
        tag: String,
        namespace: String,
        attributes: List[HtmlAttribute],
        children: List[HtmlNode]
    )
    case Text(text: String)
    case Comment(text: String)
    case Doctype(name: String, public_id: String, system_id: String)

# Escapes text for insertion into an HTML text or quoted attribute context.
export fn escape(text: String) -> String:

# Decodes HTML5 named and numeric character references in text context, once.
# Recognized references can omit semicolons; unrecognized text remains literal.
# Does not parse markup or normalize text; invalid numeric scalars become U+FFFD.
export fn unescape(text: String) -> String:

# Parses HTML into a normalized tree and applies the supplied resource limits.
export fn parse(
    text: String,
    limits: Optional[HtmlLimits] = none
) -> Result[HtmlNode, HtmlError]:

impl Error for HtmlError:
    fn message() -> String:
