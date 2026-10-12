+++
title = "url"
+++

# @std/url.ms

Import each required symbol with `import Name from "@std/url.ms"`.

## QueryEntry

Kind: record.

```text
QueryEntry: QueryEntry
field key: String
field value: String
```

## Url

Kind: record.

```text
Url: Url
field scheme: String
field host: String
field port: Optional[Int]
field path: String
field query: String
field fragment: String
```

## UrlError

Kind: alternative.

```text
UrlError: UrlError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
operation message: fn()->String
```

## decode_component

Kind: fn.

```text
decode_component: fn(text: String)->Result[String, UrlError]
```

## encode_component

Kind: fn.

```text
encode_component: fn(text: String)->String
```

## format

Kind: fn.

```text
format: fn(value: Url)->Result[String, UrlError]
```

## format_query

Kind: fn.

```text
format_query: fn(entries: List[QueryEntry])->String
```

## parse

Kind: fn.

```text
parse: fn(text: String)->Result[Url, UrlError]
```

## parse_query

Kind: fn.

```text
parse_query: fn(text: String, max_entries: Int)->Result[List[QueryEntry], UrlError]
```

## resolve

Kind: fn.

```text
resolve: fn(base: Url, reference: String)->Result[Url, UrlError]
```

