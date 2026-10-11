+++
title = "Serialization and formats"
weight = 51
+++

# Serialization and formats

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/json.ms`

```text
fn parse(text: String, limits: JsonLimits) -> Result[JsonValue, LibraryError]
fn stringify(value: JsonValue, max_bytes: Int) -> Result[String, LibraryError]
```

## `@std/csv.ms`

```text
fn parse(text: String, options: CsvOptions, max_rows: Int, max_cells: Int) -> Result[List[List[String]], LibraryError]
fn stringify(rows: List[List[String]], options: CsvOptions, max_bytes: Int) -> Result[String, LibraryError]
```

## `@std/url.ms`

```text
fn decode_component(text: String) -> Result[String, LibraryError]
fn encode_component(text: String) -> String
fn format(value: Url) -> Result[String, LibraryError]
fn format_query(entries: List[QueryEntry]) -> String
fn parse(text: String) -> Result[Url, LibraryError]
fn parse_query(text: String, max_entries: Int) -> Result[List[QueryEntry], LibraryError]
fn resolve(base: Url, reference: String) -> Result[Url, LibraryError]
```

## `@std/html.ms`

```text
fn escape(text: String) -> String
```

## Data records

```text
type JsonLimits:
    max_bytes: Int
    max_depth: Int
    max_values: Int

type JsonValue:
    case Null
    case BoolValue(value: Bool)
    case NumberValue(text: String)
    case StringValue(value: String)
    case ArrayValue(values: List[JsonValue])
    case ObjectValue(values: Map[String, JsonValue])

type CsvOptions:
    delimiter: String
    line_ending: String

type QueryEntry:
    key: String
    value: String

type Url:
    scheme: String
    host: String
    port: Optional[Int]
    path: String
    query: String
    fragment: String
```

JSON numbers retain exact valid token text, including integers larger than 2^53. Stringify validates NumberValue text, since source may construct that case directly. No reflection-based record serialization, execution hooks, or implicit Float conversion. Parse consumes one document, rejects trailing values, duplicate decoded keys, and unpaired surrogate escapes. Object order follows Map insertion order. Nonnegative limits count UTF-8 input/output bytes, container depth (root container is one), and all values (root is one; object keys are not values). Parsing and stringify also enforce a native depth ceiling of 512. Malformed data returns InvalidData; bounds return LimitExceeded. Stringify is compact and Go JSON-escapes HTML-sensitive characters; it is not a canonical signing serialization.

CSV delimiters are one non-NUL ASCII byte other than quote/CR/LF; line_ending is LF or CRLF. Row/cell/output limits are nonnegative. Go encoding/csv quoting applies: doubled quotes, no trimming or type inference, variable-width rows, ignored blank lines, and CRLF normalization including inside quoted cells. Max_cells counts all returned cells; exceeding a bound returns LimitExceeded. Input String is already resident; one record is parsed before its row/cell limit is checked. Applications must bound source reads before CSV parsing. Serialization ends every row with the selected terminator. Formula-like spreadsheet values are not rewritten.

URL parse requires an absolute hierarchical URL and rejects userinfo. Scheme/host normalize to lowercase; port is none or 0–65535. Path retains escaped separators, query remains encoded, fragment is decoded. Resolve follows Go net/url reference resolution. Url is an ordinary record: format/resolve validate source-created values. Unsupported opaque URLs return InvalidData. Query entries preserve duplicates/order; bare keys become empty values and `+` means space. Component encoding preserves only ASCII unreserved characters, and decoding rejects invalid UTF-8. IDNA normalization, absent-versus-empty query distinction, and browser WHATWG URL compatibility are deferred.

HTML escape protects text and quoted attribute contexts. It is not a sanitizer or a JavaScript/CSS/URL-context encoder.
