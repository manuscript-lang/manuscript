+++
title = "url"
+++

# @std/url.ms

Import each required symbol with `import Name from "@std/url.ms"`.

## QueryEntry {data-api-kind="Record"}

One decoded key and value in a URL query string.

```manuscript
type QueryEntry:
    key: String
    value: String
```

### QueryEntry.key

Decoded query key; duplicate keys retain separate entries in input order.

```manuscript
key: String
```

### QueryEntry.value

Decoded query value; a bare key has an empty value and plus decodes as a space.

```manuscript
value: String
```

## Url {data-api-kind="Record"}

Parsed URL components. A missing port is represented by `none`.

```manuscript
type Url:
    scheme: String
    host: String
    port: Optional[Int]
    path: String
    query: String
    fragment: String
```

### Url.fragment

Decoded fragment contents without the leading hash mark.

```manuscript
fragment: String
```

### Url.host

Lowercased hostname, excluding the port and IPv6 brackets; user information is rejected.

```manuscript
host: String
```

### Url.path

Escaped path text, retaining escaped separators; format validates its percent escapes and UTF-8.

```manuscript
path: String
```

### Url.port

Explicit numeric port in 0..65535, or none when the input has no port.

```manuscript
port: Optional[Int]
```

### Url.query

Encoded query contents without the leading question mark; parse_query decodes individual entries.

```manuscript
query: String
```

### Url.scheme

URL scheme, lowercased during parsing; native parse rejects missing schemes and opaque URLs.

```manuscript
scheme: String
```

## UrlError {data-api-kind="Alternative"}

Errors returned for malformed URL text, components, or query limits.

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

### UrlError.InvalidData

URL text, escaped bytes, port syntax or a relative reference is invalid or unsupported.

```manuscript
case InvalidData
```

### UrlError.InvalidInput

Constructed URL components or a supplied query-entry budget are invalid.

```manuscript
case InvalidInput
```

### UrlError.LimitExceeded

The decoded query has more entries than its supplied budget permits.

```manuscript
case LimitExceeded
```

### UrlError.Error.message

Returns a URL-prefixed diagnostic without echoing addresses, query values or credentials.

```manuscript
fn message() -> String:
```

## decode_component {data-api-kind="Function"}

Decodes one percent-encoded URL component. `+` is not treated as a space.

```manuscript
fn decode_component(text: String) -> Result[String, UrlError]:
```

## encode_component {data-api-kind="Function"}

Percent-encodes one URL component using UTF-8 bytes.

```manuscript
fn encode_component(text: String) -> String:
```

## format {data-api-kind="Function"}

Formats URL components as an absolute or relative URL.

```manuscript
fn format(value: Url) -> Result[String, UrlError]:
```

## format_query {data-api-kind="Function"}

Encodes query entries as a query string.

```manuscript
fn format_query(entries: List[QueryEntry]) -> String:
```

## parse {data-api-kind="Function"}

Parses an absolute URL into its components.

```manuscript
fn parse(text: String) -> Result[Url, UrlError]:
```

## parse_query {data-api-kind="Function"}

Parses a query string, preserving duplicate keys and their input order.

```manuscript
fn parse_query(text: String, max_entries: Optional[Int] = none) -> Result[List[QueryEntry], UrlError]:
```

## resolve {data-api-kind="Function"}

Resolves a relative reference against a base URL.

```manuscript
fn resolve(base: Url, reference: String) -> Result[Url, UrlError]:
```

