+++
title = "url"
+++

# @std/url.ms

Import each required symbol with `import Name from "@std/url.ms"`.

## QueryEntry {data-api-kind="Record"}

```manuscript
QueryEntry: QueryEntry
field key: String
field value: String
```

## Url {data-api-kind="Record"}

```manuscript
Url: Url
field scheme: String
field host: String
field port: Optional[Int]
field path: String
field query: String
field fragment: String
```

## decode_component {data-api-kind="Function"}

```manuscript
decode_component: fn(text: String)->Result[String, LibraryError]
```

## encode_component {data-api-kind="Function"}

```manuscript
encode_component: fn(text: String)->String
```

## format {data-api-kind="Function"}

```manuscript
format: fn(value: Url)->Result[String, LibraryError]
```

## format_query {data-api-kind="Function"}

```manuscript
format_query: fn(entries: List[QueryEntry])->String
```

## parse {data-api-kind="Function"}

```manuscript
parse: fn(text: String)->Result[Url, LibraryError]
```

## parse_query {data-api-kind="Function"}

```manuscript
parse_query: fn(text: String, max_entries: Int)->Result[List[QueryEntry], LibraryError]
```

## resolve {data-api-kind="Function"}

```manuscript
resolve: fn(base: Url, reference: String)->Result[Url, LibraryError]
```

