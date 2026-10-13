+++
title = "html"
+++

# @std/html.ms

Import each required symbol with `import Name from "@std/html.ms"`.

## HtmlAttribute {data-api-kind="Record"}

An HTML attribute, including its namespace and decoded value.

```manuscript
type HtmlAttribute:
    name: String
    namespace: String
    value: String
```

### HtmlAttribute.name

Local attribute name after native HTML parsing and normalization.

```manuscript
name: String
```

### HtmlAttribute.namespace

Attribute namespace prefix, or empty text for an unqualified attribute.

```manuscript
namespace: String
```

### HtmlAttribute.value

Decoded attribute contents, with character references resolved.

```manuscript
value: String
```

## HtmlError {data-api-kind="Alternative"}

Errors returned for malformed HTML or parser resource limits.

```manuscript
type HtmlError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for HtmlError:
    fn message() -> String:
```

### HtmlError.InvalidData

Input encoding or a native parser/tree conversion is invalid; HTML syntax can be recovered normally.

```manuscript
case InvalidData
```

### HtmlError.InvalidInput

A supplied byte, tree-depth or node-count budget is negative.

```manuscript
case InvalidInput
```

### HtmlError.LimitExceeded

Input/output bytes or parsed/serialized tree traversal exceeds a supplied budget.

```manuscript
case LimitExceeded
```

### HtmlError.Error.message

Returns an HTML-prefixed diagnostic without echoing source markup.

```manuscript
fn message() -> String:
```

## HtmlLimits {data-api-kind="Record"}

Optional bounds for HTML input/output bytes, tree depth, and node count.

```manuscript
type HtmlLimits:
    max_bytes: Optional[Int] = none
    max_depth: Optional[Int] = none
    max_nodes: Optional[Int] = none
```

### HtmlLimits.max_bytes

Maximum UTF-8 input bytes before parsing or encoded output bytes from stringify; none adds no budget.

```manuscript
max_bytes: Optional[Int] = none
```

### HtmlLimits.max_depth

Maximum node depth; the parsed document or serialized root is zero and direct children are one.

```manuscript
max_depth: Optional[Int] = none
```

### HtmlLimits.max_nodes

Maximum returned or serialized nodes, including document/text/comment/doctype and implied elements.

```manuscript
max_nodes: Optional[Int] = none
```

## HtmlNode {data-api-kind="Alternative"}

A parsed HTML document tree with document, element, text, comment, and doctype nodes.

```manuscript
type HtmlNode:
    case Document(children: List[HtmlNode])
    case Element(tag: String, namespace: String, attributes: List[HtmlAttribute], children: List[HtmlNode])
    case Text(text: String)
    case Comment(text: String)
    case Doctype(name: String, public_id: String, system_id: String)
```

### HtmlNode.Comment

An HTML comment retained as a node rather than element text.

```manuscript
case Comment(text: String)
```

### HtmlNode.Doctype

A document-type declaration retained from the parsed HTML.

```manuscript
case Doctype(name: String, public_id: String, system_id: String)
```

### HtmlNode.Document

Root document node, including any elements implied by HTML tree normalization.

```manuscript
case Document(children: List[HtmlNode])
```

### HtmlNode.Element

An element with normalized attributes and its ordered child nodes.

```manuscript
case Element(tag: String, namespace: String, attributes: List[HtmlAttribute], children: List[HtmlNode])
```

### HtmlNode.Text

Text node contents after HTML entity decoding and tree normalization.

```manuscript
case Text(text: String)
```

### HtmlNode.Comment.text

Comment contents without the opening and closing comment delimiters.

```manuscript
text: String
```

### HtmlNode.Doctype.name

Doctype name supplied by the native HTML parser.

```manuscript
name: String
```

### HtmlNode.Doctype.public_id

Public identifier, or empty text when no public identifier is present.

```manuscript
public_id: String
```

### HtmlNode.Doctype.system_id

System identifier, or empty text when no system identifier is present.

```manuscript
system_id: String
```

### HtmlNode.Document.children

Direct child nodes in normalized document order.

```manuscript
children: List[HtmlNode]
```

### HtmlNode.Element.attributes

Attributes in parser order, with decoded values and namespace information.

```manuscript
attributes: List[HtmlAttribute]
```

### HtmlNode.Element.children

Direct child nodes in normalized tree order; mutable list storage is retained.

```manuscript
children: List[HtmlNode]
```

### HtmlNode.Element.namespace

Element namespace, such as svg/math, or empty text for ordinary HTML.

```manuscript
namespace: String
```

### HtmlNode.Element.tag

Local element tag name produced by the HTML parser.

```manuscript
tag: String
```

### HtmlNode.Text.text

Unicode text belonging to this node, without surrounding markup.

```manuscript
text: String
```

## escape {data-api-kind="Function"}

Escapes text for insertion into an HTML text or quoted attribute context.

```manuscript
fn escape(text: String) -> String:
```

## parse {data-api-kind="Function"}

Parses HTML into a normalized tree and applies the supplied resource limits.

```manuscript
fn parse(text: String, limits: Optional[HtmlLimits] = none) -> Result[HtmlNode, HtmlError]:
```

## stringify {data-api-kind="Function"}

Renders an HTML node or document with HTML5 escaping and raw-text element rules.
Cycles and malformed nodes return InvalidData; limits bound output bytes, root-zero depth and node count.
Doctype identifiers containing > or both quote delimiters return InvalidData.
Parsing the output normalizes the tree and can insert implied document elements.

```manuscript
fn stringify(value: HtmlNode, limits: Optional[HtmlLimits] = none) -> Result[String, HtmlError]:
```

## unescape {data-api-kind="Function"}

Decodes HTML5 named and numeric character references in text context, once.
Recognized references can omit semicolons; unrecognized text remains literal.
Does not parse markup or normalize text; invalid numeric scalars become U+FFFD.

```manuscript
fn unescape(text: String) -> String:
```

