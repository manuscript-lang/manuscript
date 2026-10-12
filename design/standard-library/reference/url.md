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

## decode_component {data-api-kind="Function"}

```manuscript
fn decode_component(text: String) -> Result[String, LibraryError]
```

## encode_component {data-api-kind="Function"}

```manuscript
fn encode_component(text: String) -> String
```

## format {data-api-kind="Function"}

```manuscript
fn format(value: Url) -> Result[String, LibraryError]
```

## format_query {data-api-kind="Function"}

```manuscript
fn format_query(entries: List[QueryEntry]) -> String
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String) -> Result[Url, LibraryError]
```

## parse_query {data-api-kind="Function"}

```manuscript
fn parse_query(text: String, max_entries: Int) -> Result[List[QueryEntry], LibraryError]
```

## resolve {data-api-kind="Function"}

```manuscript
fn resolve(base: Url, reference: String) -> Result[Url, LibraryError]
```

