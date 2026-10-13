+++
title = "html"
+++

# @std/html.ms

Import each required symbol with `import Name from "@std/html.ms"`.

## HtmlAttribute {data-api-kind="Record"}

```manuscript
type HtmlAttribute:
    name: String
    namespace: String
    value: String
```

## HtmlError {data-api-kind="Alternative"}

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

```manuscript
type HtmlLimits:
    max_bytes: Optional[Int] = none
    max_depth: Optional[Int] = none
    max_nodes: Optional[Int] = none
```

## HtmlNode {data-api-kind="Alternative"}

```manuscript
type HtmlNode:
    case Document(children: List[HtmlNode])
    case Element(tag: String, namespace: String, attributes: List[HtmlAttribute], children: List[HtmlNode])
    case Text(text: String)
    case Comment(text: String)
    case Doctype(name: String, public_id: String, system_id: String)
```

## escape {data-api-kind="Function"}

```manuscript
fn escape(text: String) -> String:
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String, limits: Optional[HtmlLimits] = none) -> Result[HtmlNode, HtmlError]:
```

