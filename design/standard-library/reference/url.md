+++
title = "url"
+++

# @std/url.ms

Import each required symbol with `import Name from "@std/url.ms"`.

## QueryEntry

Kind: record.

```manuscript
QueryEntry: QueryEntry
field key: String
field value: String
```

## Url

Kind: record.

```manuscript
Url: Url
field scheme: String
field host: String
field port: Optional[Int]
field path: String
field query: String
field fragment: String
```

## decode_component

Kind: fn.

```manuscript
decode_component: fn(text: String)->Result[String, LibraryError]
```

## encode_component

Kind: fn.

```manuscript
encode_component: fn(text: String)->String
```

## format

Kind: fn.

```manuscript
format: fn(value: Url)->Result[String, LibraryError]
```

## format_query

Kind: fn.

```manuscript
format_query: fn(entries: List[QueryEntry])->String
```

## parse

Kind: fn.

```manuscript
parse: fn(text: String)->Result[Url, LibraryError]
```

## parse_query

Kind: fn.

```manuscript
parse_query: fn(text: String, max_entries: Int)->Result[List[QueryEntry], LibraryError]
```

## resolve

Kind: fn.

```manuscript
resolve: fn(base: Url, reference: String)->Result[Url, LibraryError]
```

