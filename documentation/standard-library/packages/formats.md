+++
title = "Serialization and formats"
weight = 51
+++

# Serialization and formats

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use these modules to parse and write JSON, CSV, and URLs, or parse HTML into a tree and escape HTML text. Choose explicit limits for input size and nesting. Each format has its own validation rules, described after the signatures.

## `@std/json.ms`

```manuscript
fn parse(text: String, limits: Optional[JsonLimits]) -> Result[JsonValue, JsonError]
fn stringify(value: JsonValue, max_bytes: Optional[Int]) -> Result[String, JsonError]
```

## `@std/csv.ms`

```manuscript
fn parse(text: String, options: CsvOptions, max_rows: Optional[Int], max_cells: Optional[Int]) -> Result[List[List[String]], CsvError]
fn stringify(rows: List[List[String]], options: CsvOptions, max_bytes: Optional[Int]) -> Result[String, CsvError]
```

## `@std/url.ms`

```manuscript
fn decode_component(text: String) -> Result[String, UrlError]
fn encode_component(text: String) -> String
fn format(value: Url) -> Result[String, UrlError]
fn format_query(entries: List[QueryEntry]) -> String
fn parse(text: String) -> Result[Url, UrlError]
fn parse_query(text: String, max_entries: Optional[Int]) -> Result[List[QueryEntry], UrlError]
fn resolve(base: Url, reference: String) -> Result[Url, UrlError]
```

## `@std/html.ms`

```manuscript
fn escape(text: String) -> String
fn parse(text: String, limits: Optional[HtmlLimits] = none) -> Result[HtmlNode, HtmlError]
```

## Data records

```manuscript
type JsonLimits:
    max_bytes: Optional[Int]
    max_depth: Optional[Int]
    max_values: Optional[Int]

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

## JSON behavior

JSON numbers keep their exact valid token text, including integers larger than 2^53. They are not automatically converted to `Float`. `stringify` also validates `NumberValue` text because an application can construct that case directly.

Parsing accepts one document. It rejects trailing values, duplicate decoded object keys, and unpaired surrogate escapes. Object order follows Map insertion order. There is no reflection-based record serialization or execution hook.

`JsonLimits` uses nonnegative limits:

| Limit | What it counts |
| --- | --- |
| `max_bytes` | UTF-8 input bytes. Stringify separately limits output bytes. |
| `max_depth` | Container nesting; a root container has depth one. |
| `max_values` | All values, including the root. Object keys are not counted as values. |

Omitted budgets impose no added byte, item, or nesting cap. Stringify rejects cyclic values. Malformed data returns `InvalidData`; exceeded limits return `LimitExceeded`.

Stringify produces compact JSON and uses Go's escaping for HTML-sensitive characters. It is not a canonical format for signing.

## CSV behavior

The delimiter must be one non-NUL ASCII byte other than quote, CR, or LF. `line_ending` is LF or CRLF. Row, cell, and output limits must be nonnegative; `max_cells` counts every returned cell.

Go's `encoding/csv` quoting rules apply: quotes are doubled, values are not trimmed or converted to other types, rows may have different widths, and blank lines are ignored. CRLF is normalized, including inside quoted cells. Serialization ends every row with the selected terminator. Formula-like spreadsheet values are left as supplied.

Exceeded limits return `LimitExceeded`. The input String is already in memory, and the parser reads one record before checking its row and cell limits. Bound the source read before parsing untrusted CSV.

## URL behavior

`parse` requires an absolute hierarchical URL and rejects user information. Scheme and host become lowercase. The optional port is in the range 0–65535.

The path keeps escaped separators, the query stays encoded, and the fragment is decoded. `resolve` follows Go's `net/url` rules. `Url` is an ordinary record, so `format` and `resolve` validate values constructed by application code too. Unsupported opaque URLs return `InvalidData`.

Query entries retain duplicates and order. A bare key has an empty value; `+` represents a space. Component encoding preserves only ASCII unreserved characters. Decoding rejects invalid UTF-8.

IDNA normalization, a distinction between absent and empty queries, and browser WHATWG URL compatibility remain future work.

## HTML parsing and escaping

`parse` returns an `HtmlNode.Document` containing an HTML5 tree. Match `Element` to work with its tag, namespace, ordered `List[HtmlAttribute]`, and child nodes. `Text`, `Comment`, and `Doctype` preserve their data. These are ordinary Manuscript data values; child lists and attribute records are mutable.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {parse, HtmlNode} from "@std/html.ms"
import {Result} from "@std/result.ms"
import Error from "@std/errors.ms"
import panic from "@std/faults.ms"

fn text_content(node: HtmlNode) -> String:
    match node:
        Text(text): return text
        Document(children):
            var text = ""
            for child in children: text = "{text}{text_content(child)}"
            return text
        Element(_, _, _, children):
            var text = ""
            for child in children: text = "{text}{text_content(child)}"
            return text
        _: return ""

fn read_text() -> Result[String, Error]:
    let document = try parse(text: "<p>Hello <b>world</b> &amp; friends</p>")
    return ok(value: text_content(document))

test "read HTML text":
    match read_text():
        ok(text):
            if text != "Hello world & friends": return panic("unexpected text")
        error(cause): return panic(cause.message())
```

Parsing follows HTML5 document rules: omitted `html`, `head`, `body`, and table structure are inserted, ordinary HTML names become lowercase, and incomplete or misnested markup is recovered. A snippet is parsed as a document, rather than in a supplied fragment context. Text and attribute entities are decoded; raw script/style text follows HTML5 rules. Attribute order is preserved, including duplicate attributes retained by the parser. HTML namespaces are empty; foreign elements use `svg` or `math`, and namespaced attributes use prefixes such as `xlink`. A doctype's absent public/system identifiers are empty strings. Scripts are retained as text and never executed.

`HtmlLimits` fields are optional and nonnegative:

| Limit | What it counts |
| --- | --- |
| `max_bytes` | UTF-8 input bytes, checked before parsing. |
| `max_depth` | Returned node depth; the document is depth zero. |
| `max_nodes` | All returned nodes, including the document, text, comments, doctypes, and inserted elements. Attributes are excluded. |

Omitted limits impose no added cap. An empty input produces four nodes (`Document`, `html`, `head`, and `body`) with maximum depth two. Depth and node budgets are checked while converting the native tree, after HTML5 parsing has allocated it; use a byte budget to bound the input first. Negative limits return `HtmlError.InvalidInput`, invalid UTF-8 or a native parser failure returns `InvalidData`, and exceeded budgets return `LimitExceeded`. Recoverable markup errors are accepted.

`escape` handles text and quoted attribute contexts. It does not sanitize HTML or encode JavaScript, CSS, or URL contexts.
