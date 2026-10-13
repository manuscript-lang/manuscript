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

## HtmlLimits {data-api-kind="Record"}

Optional bounds for HTML input bytes, tree depth, and node count.

```manuscript
type HtmlLimits:
    max_bytes: Optional[Int64] = none
    max_depth: Optional[Int] = none
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

## unescape {data-api-kind="Function"}

Decodes HTML5 named and numeric character references in text context, once.
Recognized references can omit semicolons; unrecognized text remains literal.
Does not parse markup or normalize text; invalid numeric scalars become U+FFFD.

```manuscript
fn unescape(text: String) -> String:
```

