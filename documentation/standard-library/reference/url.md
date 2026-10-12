+++
title = "url"
+++

# @std/url.ms

Import each required symbol with `import Name from "@std/url.ms"`.

## QueryEntry {data-api-kind="Record"}

```manuscript
type QueryEntry:
    key: String
    value: String
```

## Url {data-api-kind="Record"}

```manuscript
type Url:
    scheme: String
    host: String
    port: Optional[Int]
    path: String
    query: String
    fragment: String
```

## UrlError {data-api-kind="Alternative"}

```manuscript
type UrlError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for UrlError:
    fn message() -> String:
```

## decode_component {data-api-kind="Function"}

```manuscript
fn decode_component(text: String) -> Result[String, UrlError]:
```

## encode_component {data-api-kind="Function"}

```manuscript
fn encode_component(text: String) -> String:
```

## format {data-api-kind="Function"}

```manuscript
fn format(value: Url) -> Result[String, UrlError]:
```

## format_query {data-api-kind="Function"}

```manuscript
fn format_query(entries: List[QueryEntry]) -> String:
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String) -> Result[Url, UrlError]:
```

## parse_query {data-api-kind="Function"}

```manuscript
fn parse_query(text: String, max_entries: Optional[Int] = none) -> Result[List[QueryEntry], UrlError]:
```

## resolve {data-api-kind="Function"}

```manuscript
fn resolve(base: Url, reference: String) -> Result[Url, UrlError]:
```

