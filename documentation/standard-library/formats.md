+++
title = "Data formats"
weight = 8
+++

# Data formats

API reference: [json](reference/json.md), [yaml](reference/yaml.md), [toml](reference/toml.md), [csv](reference/csv.md), [url](reference/url.md), [html](reference/html.md).

Use these modules to parse and write JSON, YAML, TOML, CSV, URLs, and HTML trees, or escape HTML text. Choose explicit limits for input size and nesting. Each format has its own validation rules.

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

Stringify produces compact JSON and escapes `<`, `>`, and `&` as `\u003c`, `\u003e`, and `\u0026`. It is not a canonical format for signing.

## YAML behavior

The parser is written in Manuscript. It reads one YAML 1.2 configuration document with textual mapping keys, block and flow collections, compact sequences and mappings, comments, quoted strings and Unicode escapes, continued scalars, and literal/folded block scalars with indentation and chomping indicators. It accepts a BOM, normalized line endings, document markers, and the `%YAML 1.2` directive.

`YamlValue` represents null, booleans, exact number text, strings, lists, and insertion-ordered maps. Core-schema booleans include `true` and `false` with YAML capitalization; `yes`, `no`, and dates remain strings. Plain mapping keys retain their text; quoted keys are decoded before duplicate checking.

Anchors and previously defined aliases retain the same value references. Forward and recursive aliases fail. Merge keys accept a mapping or a list of mappings; earlier mappings win and explicit entries override merged values. Duplicate explicit keys fail.

Continued plain and quoted scalars fold adjacent lines to a space and retain one newline per intervening blank line. Quoted folding discards surrounding physical whitespace; double-quoted escaped continuations discard the first break while preserving preceding content whitespace. Folded blocks (`>`) use the same paragraph rule between ordinary lines and preserve breaks around more-indented content. Literal blocks (`|`) retain their line breaks. Block chomping controls final breaks, including trailing blank lines; a missing final line ending is not added.

This configuration parser does not implement the complete YAML specification: explicit tags, complex/explicit mapping keys, custom directives, multiple documents, and flow sequence mapping shorthand are unsupported. Specialized flow indentation rules are not fully implemented. `UnsupportedFeature` identifies explicit tags, complex keys, and unsupported directives; other malformed or unsupported forms return `InvalidData` with a one-based line, column, and reason. Positions identify the offending token: merge-key errors point at the `<<` key and block-scalar header errors at the offending header character.

## TOML behavior

The parser is written in Manuscript and targets TOML 1.0. The result is a `TableValue`, including for an empty document. Values include strings, signed 64-bit integers, binary64 floats, booleans, date/time token text, lists, and insertion-ordered tables.

It supports bare/quoted/dotted keys, explicit and implicit tables, arrays of tables, heterogeneous arrays, closed inline tables, comments, literal/basic strings, multiline strings, Unicode escapes, and escaped newline folding. Integers support decimal, hexadecimal, octal, and binary forms with valid underscore separators; floats include exponents, infinities, and NaN. Date/time values preserve their spelling and fractional precision after checking calendar/time fields. No host timezone conversion occurs.

Duplicate keys, table redefinitions, scalar/table conflicts, extensions to closed inline tables, malformed strings/numbers/dates, out-of-range integers, trailing text, and bare carriage returns fail with `InvalidData(line, column, reason)`. CRLF becomes LF. Control characters and bare carriage returns report their own line and column, and a bad bare value (such as `True` or `yes`) reports `invalid value` at the token start. Dates allow leap-second spelling (`60`) without checking a historical leap-second registry. Binary64 conversion rejects overflowing finite float tokens. TOML 1.1 extensions are outside this parser's contract.

## YAML and TOML limits

`YamlLimits` and `TomlLimits` each contain `max_bytes`, `max_depth`, and `max_values`, all `Optional[Int]`. Their ordinary record constructors require all three fields; use `none` for each omitted budget. Omitting `limits` or passing `none` adds no cap.

- `max_bytes` counts UTF-8 input bytes before normalization.
- `max_depth` counts every value level, with the root at one, including scalar leaves and implicit TOML tables.
- `max_values` counts containers and leaves, excluding keys. YAML checks both parsed values and the returned tree with aliases counted at each occurrence; merge-source values also consume the parsing budget.

Negative limits return `InvalidInput`; zero is a real budget and exhaustion returns `LimitExceeded`. Empty YAML still returns one null value; empty TOML returns one table. Limits are checked during parsing and against the completed result. Input text and the parser's character/line lists are already allocated; these budgets do not provide a general memory or CPU sandbox. With no budgets, YAML aliases are returned without traversing their expanded tree.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {parse, TomlValue, TomlLimits} from "@std/toml.ms"
import panic from "@std/faults.ms"

test "parse bounded TOML configuration":
    let limits = TomlLimits(max_bytes: 1024, max_depth: 8, max_values: 64)
    match parse(text: "[server]\nport = 8080\n", limits: limits):
        error(cause): return panic(cause.message())
        ok(value):
            match value:
                TableValue(entries):
                    if not entries.contains("server"): return panic("missing server table")
                _: return panic("expected table")
```

## CSV behavior

`CsvOptions()` creates fresh mutable options with `delimiter: ","` and `line_ending: "\n"`. `parse(text: "a,b\n")` and `stringify(rows: [["a", "b"]])` use these defaults. Either option field can be supplied independently; use `CsvOptions(line_ending: "\r\n")` for CRLF output. Explicit options retain their values and are validated as usual.

The delimiter must be one non-NUL ASCII byte other than quote, CR, or LF. `line_ending` is LF or CRLF. Row, cell, and output limits must be nonnegative; `max_cells` counts every returned cell.

CSV quotes are doubled; values are not trimmed or converted to other types, rows may have different widths, and blank lines are ignored. CRLF is normalized, including inside quoted cells. Serialization ends every row with the selected terminator. Formula-like spreadsheet values are left as supplied.

A row containing one empty string is serialized as a quoted empty field (`""`), so parsing retains it. A row with no cells is serialized as a blank line and is skipped on parsing; these two rows have distinct serialized forms. Multiple empty cells retain their delimiters.

Exceeded limits return `LimitExceeded`. The input String is already in memory, and the parser reads one record before checking its row and cell limits. Bound the source read before parsing untrusted CSV.

## URL behavior

`parse` requires an absolute hierarchical URL and rejects user information. Scheme and host become lowercase. The optional port is in the range 0–65535.

The path keeps escaped separators, the query stays encoded, and the fragment is decoded. Resolving a relative URL merges it with the base path and removes dot segments. `Url` is an ordinary record, so `format` and `resolve` validate values constructed by application code too. Unsupported opaque URLs return `InvalidData`.

Query entries retain duplicates and order. A bare key has an empty value; `+` represents a space. Component encoding preserves only ASCII unreserved characters. Decoding rejects invalid UTF-8.

Hostnames are not normalized through IDNA; absent and empty queries have the same representation.

## HTML parsing and escaping

`parse` returns an `HtmlNode.Document` containing an HTML5 tree. Match `Element` to work with its tag, namespace, ordered `List[HtmlAttribute]`, and child nodes. `Text`, `Comment`, and `Doctype` preserve their data. These are ordinary Manuscript data values; child lists and attribute records are mutable.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {parse, HtmlNode} from "@std/html.ms"
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
    return ok(text_content(document))

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

`escape` handles text and quoted attribute contexts. It does not sanitize HTML or escape script, stylesheet, or URL content.
