# Canonical standard-library declarations. Implementations are native.

# Errors returned for malformed JSON or configured input and nesting limits.
export type JsonError:
    # An explicit input, depth, value-count or output budget is negative.
    case InvalidInput
    # JSON syntax, Unicode escapes, duplicate keys, number text or a cyclic value is invalid.
    case InvalidData
    # The input, nesting, value count or encoded output exceeds a supplied budget.
    case LimitExceeded

# Optional bounds for JSON input bytes, nesting depth, and parsed values.
export type JsonLimits:
    # Maximum UTF-8 input bytes before parsing; none adds no input-size budget.
    max_bytes: Optional[Int] = none
    # Maximum container nesting; a root scalar has depth zero, and a root container depth one.
    max_depth: Optional[Int] = none
    # Maximum parsed containers and scalar values, excluding object keys; none adds no count budget.
    max_values: Optional[Int] = none

# A JSON value. Number text is retained to avoid losing precision during parsing.
export type JsonValue:
    # JSON null, represented without a payload value.
    case Null
    # A JSON true or false value.
    case BoolValue(
        # The decoded boolean, without a textual representation requirement.
        value: Bool
    )
    # An exact JSON number token; parsing does not coerce it into Float.
    case NumberValue(
        # Original numeric token text; stringify validates its JSON number syntax.
        text: String
    )
    # A decoded JSON string, with escapes resolved into Unicode text.
    case StringValue(
        # Decoded UTF-8 text, preserving scalar contents without normalization.
        value: String
    )
    # An ordered JSON array whose mutable list can be updated before serialization.
    case ArrayValue(
        # Element values in source order; nested mutable payloads retain their references.
        values: List[JsonValue]
    )
    # A JSON object retaining insertion order and rejecting duplicate keys during parsing.
    case ObjectValue(
        # String-keyed members in insertion order; stringify reads their current values.
        values: Map[String, JsonValue]
    )

# Parses one JSON value and applies the supplied input, depth, and value limits.
#
# With the default `T = JsonValue` the result is the parsed tree. Any other `T` is read from the
# document by the inverse of the `stringify` encoding, so `parse[Request](text)` and `let request: Request = parse(text)`
# build a `Request` directly (`try` passes no expected type, so write `try parse[Request](text)`). A value whose shape does not match `T` returns
# `InvalidData`; nothing is rejected at compile time, as with `stringify`. Input, depth and value limits
# apply to the document before decoding.
#
# - A record is an object. Members may appear in any order. An absent member takes the field's default,
#   else `none` for an `Optional` field; an absent required field returns `InvalidData`, so a field
#   with no JSON form (a function, say) needs a default to be readable. A member that is not a field
#   is ignored, unless `ignore_unknown_fields` is `false`, which makes it return `InvalidData`.
# - An alternative case without payload is its name as a string; one with payload is externally tagged,
#   `{"Circle":{"radius":2}}`, with the same member rules for the labeled fields. Standard alternatives such
#   as `Result` and the error types follow the same rule, so `{"ok":{"value":5}}` reads as `ok(5)`.
# - `Optional[T]` reads `null` as `none`. `List` and `Set` read arrays (a `Set` drops repeated elements).
# - `Map[K, V]` reads an object, converting each member name to `K` from its string form (two names that read as the same key, such as `"1"` and `"01"` for `Int`, return `InvalidData`): `String`
#   as is, `Int`, `BigInt`, `Decimal`, `Float` and `Bool` from their text, `Timestamp` from RFC 3339,
#   `Duration` from nanoseconds, and a payloadless case from its name. Other key types return
#   `InvalidData`.
# - `Int` accepts integer digits that fit in 64 bits, `Float` any finite number, `BigInt` and `Decimal`
#   the exact number text. A `null` Float, which `stringify` writes for `NaN` and infinities, returns
#   `InvalidData`.
# - `Timestamp` reads an RFC 3339 string, `Duration` integer nanoseconds, `Bytes` a standard base64
#   string, and `Url`, `IpAddress` and `Cidr` their string forms.
# - `JsonValue` keeps its subtree as parsed.
#
# The object-or-map choice comes from `T`, not from the text: `parse[Request]` reads an object as a
# record and `parse[Map[String, Int]]` reads the same object as a map.
export fn parse[T = JsonValue](
    text: String,
    limits: Optional[JsonLimits] = none,
    ignore_unknown_fields: Bool = true
) -> Result[T, JsonError]:

# Customizes how `stringify` encodes a type, like JavaScript's `toJSON`. It takes precedence over the
# structural encoding for every record and alternative, so it is the way to choose a tagged or
# discriminator encoding, or any other shape. A value whose type implements it is encoded as the
# `JsonValue` its `to_json` returns, wherever it appears: at the root, in a field, in a list, or as a map
# value. The returned `JsonValue` is written as stored and is not customized again. Implement it in the
# module that defines the type. A planned counterpart, `JsonDecode` with a static
# `from_json(value: JsonValue) -> Result[Self, JsonError]`, will let a type choose its own typed parse;
# it does not exist yet.
#
# The default encoding of an alternative is externally tagged, `{"Created":{"id":1}}`, so a structural
# encoding round-trips. This implementation writes an internal `type` discriminator instead, a common
# protocol shape:
#
# ```manuscript
# type Event:
#     case Created(id: Int)
#     case Deleted(id: Int)
#
# impl JsonEncode for Event:
#     fn to_json() -> JsonValue:
#         match self:
#             Created(id): return tagged("created", id)
#             Deleted(id): return tagged("deleted", id)
#
# fn tagged(kind: String, id: Int) -> JsonValue:
#     let fields = Map[String, JsonValue]().add("type", JsonValue.StringValue(kind))
#     return JsonValue.ObjectValue(fields.add("id", JsonValue.NumberValue("{id}")))
# ```
export interface JsonEncode:
    # Returns the JSON form of this value.
    fn to_json() -> JsonValue

# Encodes any value as JSON text, the way JavaScript's `JSON.stringify` does. Every type is accepted;
# a value with no JSON form is omitted or written as `null` rather than rejected at compile time.
#
# - Record fields appear in declaration order. A field holding `none` is omitted; so is a field
#   holding a value with no JSON form (a function, a resource, an interface value, `Unit`, or an `Instant`).
# - `none` elsewhere (a list element, a map value, the root) is `null`, as is a no-form list element.
#   `Optional[Optional[T]]` is allowed: `some(none)` is `null` and `none` is omitted.
# - A map value with no JSON form is omitted. A root value with no JSON form returns `InvalidData`.
# - An alternative case without payload is its name as a string, `"Dot"`. A case with payload is
#   externally tagged: `{"Circle":{"radius":2}}`, an object keyed by the case name whose value holds
#   the labeled fields under the record rules. Payload labels never collide with a discriminator.
# - Map entries and Set elements keep insertion order. A map key becomes its string form: `String`
#   as is, `Int`, `BigInt`, `Decimal`, `Float` and `Bool` as their text, a `Timestamp` as RFC 3339,
#   and a case without payload as its name. Any other key type returns `InvalidData`.
# - Int, BigInt and Decimal are exact decimal digits. Float uses the shortest decimal that parses
#   back to the same value; NaN and infinities are `null`.
# - `Timestamp` is an RFC 3339 string in UTC, `Duration` its integer nanoseconds, `Bytes` a standard
#   base64 string, `Url` its string form, `IpAddress` and `Cidr` their text. `Result`, other standard records and
#   alternatives follow the ordinary rules, so `ok(5)` is `{"ok":{"value":5}}`.
# - A `JsonValue` is written as stored, so parsed documents mix with typed data.
# - A type that implements `JsonEncode` is written as the `JsonValue` its `to_json` returns, instead of any rule above.
# - Strings are UTF-8 JSON strings; `<`, `>` and `&` are written as Unicode escapes.
# - Values are read when `stringify` runs, so later mutation does not change the text. A value reachable
#   from itself returns `InvalidData`; shared but acyclic values are written each time they appear.
#
# `indent` pretty-prints with that many spaces per level, at most 10; none or 0 is compact. Empty
# containers stay `{}` and `[]`, and a space follows each colon. `max_bytes` bounds the output,
# indentation included; exceeding it returns `LimitExceeded`. A negative bound or indent returns
# `InvalidInput`.
#
# ```manuscript
# type Request:
#     model: String
#     stream: Bool
#     user: Optional[String]
#
# stringify(value: Request(model: "example", stream: true, user: none))
# ```
export fn stringify[T](
    value: T,
    max_bytes: Optional[Int] = none,
    indent: Optional[Int] = none
) -> Result[String, JsonError]:

impl Error for JsonError:
    # Returns a JSON-prefixed diagnostic without echoing input text or number tokens.
    fn message() -> String:

# documentation documentation/standard-library/formats.md
# +++
# title = "Data formats"
# weight = 8
# +++
#
# # Data formats
#
# API reference: [json](reference/json.md), [yaml](reference/yaml.md), [toml](reference/toml.md), [csv](reference/csv.md), [url](reference/url.md), [html](reference/html.md).
#
# Use these modules to parse and write JSON, YAML, TOML, CSV, URLs, and HTML trees, or escape HTML text. Choose explicit limits for input size and nesting. Each format has its own validation rules.
#
# ## JSON behavior
#
# JSON numbers keep their exact valid token text, including integers larger than 2^53. They are not automatically converted to `Float`. `stringify` also validates `NumberValue` text because an application can construct that case directly.
#
# Parsing accepts one document. It rejects trailing values, duplicate decoded object keys, and unpaired surrogate escapes. Object order follows Map insertion order.
#
# `JsonLimits` uses nonnegative limits:
#
# | Limit | What it counts |
# | --- | --- |
# | `max_bytes` | UTF-8 input bytes. Stringify separately limits output bytes. |
# | `max_depth` | Container nesting; a root container has depth one. |
# | `max_values` | All values, including the root. Object keys are not counted as values. |
#
# Omitted budgets impose no added byte, item, or nesting cap. Stringify rejects cyclic values. Malformed data returns `InvalidData`; exceeded limits return `LimitExceeded`.
#
# ### Incremental JSON decoding
#
# `decoder` in `@std/jsonstream.ms` returns a `JsonDecoder` for byte streams. `feed(chunk)` accepts a chunk of any size and returns the values it completes; `finish()` ends the input. Strings, escapes, numbers, nesting, and UTF-8 scalars may be split across chunks, and braces or newlines inside strings never end a value.
#
# The decoder reads concatenated values, which covers JSON Lines. Values are separated by JSON whitespace, or directly adjacent when they are strings, arrays, or objects. A top-level number, `true`, `false`, or `null` ends at whitespace or at `finish()`. Blank lines are skipped, and a value may span several lines. Input that ends inside a string, array, or object is `InvalidData` at `finish()`. `JsonError` carries no byte offsets.
#
# The optional `JsonLimits` apply to each value: `max_bytes` counts its UTF-8 bytes, `max_depth` its nesting, and `max_values` its parsed values. The decoder buffers only the unfinished value and drops that buffer after an error, so supply `max_bytes` for untrusted input. After an error the decoder stays failed and repeats that error, and an error discards values completed earlier in the same chunk. Calls after `finish()` return `InvalidInput`. The decoder only consumes chunks you give it; it never reads, owns, or closes a stream, so pass chunks from `ReadStream.read` or an HTTP response body and close those yourself.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import decoder from "@std/jsonstream.ms"
# import panic from "@std/faults.ms"
#
# test "decode JSON Lines split across chunks":
#     let reader = decoder().unwrap()
#     let first = reader.feed("\{\"id\":1\}\n\{\"id".to_bytes()).unwrap()
#     let second = reader.feed("\":2\}\n".to_bytes()).unwrap()
#
#     if first.length() != 1 or second.length() != 1: return panic("expected one value per feed")
#     if reader.finish().unwrap().length() != 0: return panic("unexpected trailing value")
# ```
#
# ### Writing JSON from Manuscript values
#
# `stringify` accepts a value of any type and writes it directly, so a request body needs no `JsonValue` wrapping. It follows JavaScript's `JSON.stringify` where Manuscript has a sound analogue: nothing is rejected at compile time, a value with no JSON form is left out or written as `null`, and a type customizes its encoding with `JsonEncode`, the analogue of `toJSON`.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {stringify, JsonEncode, JsonValue} from "@std/json.ms"
# import panic from "@std/faults.ms"
#
# type Message:
#     role: String
#     content: String
#
# type Request:
#     model: String
#     stream: Bool
#     user: Optional[String]
#     messages: List[Message]
#
# type Money:
#     cents: Int
#
# impl JsonEncode for Money:
#     fn to_json() -> JsonValue:
#         return JsonValue.StringValue("usd:{self.cents}")
#
# test "stringify encodes typed values":
#     let request = Request(
#         model: "example",
#         stream: true,
#         user: none,
#         messages: [Message(role: "user", content: "hi")]
#     )
#     let expected = "\{\"model\":\"example\",\"stream\":true,\"messages\":[\{\"role\":\"user\",\"content\":\"hi\"\}]\}"
#     if stringify(value: request).unwrap() != expected: return panic("unexpected request body")
#     if stringify(value: Money(cents: 250)).unwrap() != "\"usd:250\"": return panic("to_json hook")
#     if stringify(value: [1], indent: 2).unwrap() != "[\n  1\n]": return panic("indent")
# ```
#
# How each value is written, and the JavaScript behavior it follows:
#
# | Value | JSON |
# | --- | --- |
# | Record | Object with fields in declaration order. |
# | Field holding `none`, a function, a resource, `Unit`, or an `Instant` | The member is omitted, as JavaScript omits `undefined` and functions. |
# | `none` anywhere else (root, list element, map value) | `null`. `some(x)` encodes as `x`; `Optional[Optional[T]]` is allowed, and `some(none)` is `null`. |
# | List element or Set element with no JSON form | `null`. |
# | Map value with no JSON form | The entry is omitted. |
# | Root value with no JSON form | `Result.error(InvalidData)`, where JavaScript returns `undefined`. |
# | Alternative case without payload | The case name as a string: `"Dot"`. |
# | Alternative case with payload | Externally tagged: `{"Circle":{"radius":2}}`, the case name keying an object of its labeled fields under the record rules. Cases with identical labels stay distinct, and the form can be decoded back. Use `JsonEncode` for a different shape. |
# | `List`, `Set` | Array in list order or set insertion order. |
# | `Map` | Object in insertion order. A key becomes its string form, as in JavaScript: `String` as is; `Int`, `BigInt`, `Decimal`, `Float` and `Bool` as text; `Timestamp` as RFC 3339; `Duration` as nanoseconds; a case without payload as its name. Any other key type returns `InvalidData`. |
# | `Int`, `BigInt`, `Decimal` | Exact decimal digits. |
# | `Float` | Shortest decimal that parses back to the same `Float`, without a trailing `.0`; an exponent only below `1e-6` or from `1e21`. `NaN` and infinities are `null`. |
# | `Timestamp` | RFC 3339 string in UTC, the analogue of `Date.toJSON`. An `Instant` is a monotonic clock reading with no calendar meaning, so it has no JSON form. |
# | `Duration` | Integer nanoseconds. |
# | `Bytes` | Standard base64 string with padding. |
# | `Url`, `IpAddress`, `Cidr` | Their string form. |
# # | `Result` and other standard records and alternatives | Ordinary record and alternative rules: `ok(5)` is `{"ok":{"value":5}}` and `error(cause)` is `{"error":{"cause":...}}`. |
# | A value held through an interface (including `Error`) | No JSON form. |
# | `JsonValue` | Written as stored, validating `NumberValue` text. |
# | A type implementing `JsonEncode` | The `JsonValue` its `to_json` returns, written as stored. It overrides every other row, including the alternative rows, so it is how to write a tagged encoding. |
#
# `stringify` reads the value when it runs and returns a new `String`, so later mutation does not change the text. A value that reaches itself returns `InvalidData`, where JavaScript throws; one value referenced twice without a cycle is written twice. `max_bytes` bounds the output, indentation included, and returns `LimitExceeded` when exceeded.
#
# `indent` is the analogue of the `space` argument: it pretty-prints with that many spaces per level, up to 10 as in JavaScript. `none` and `0` are compact; a negative value returns `InvalidInput`. Empty arrays and objects stay `[]` and `{}`. There is no replacer function; build the shape you want as a record or a `JsonEncode` implementation. A `JsonDecode` interface to customize typed parsing is planned and not available yet.
#
# ### Reading JSON into Manuscript values
#
# `parse` returns a `JsonValue` unless `T` is named, either explicitly or through the expected result, in which case it builds that type by the inverse of the `stringify` encoding. The object-or-map choice comes from `T`, not from the text.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {parse, JsonError} from "@std/json.ms"
# import panic from "@std/faults.ms"
#
# type Message:
#     role: String
#     content: String
#
# type Request:
#     model: String
#     stream: Bool = false
#     user: Optional[String]
#     messages: List[Message]
#
# fn read_request(text: String) -> Result[Request, JsonError]:
#     let request = try parse[Request](text)
#     return ok(request)
#
# test "parse builds typed values":
#     let text = "\{\"model\":\"example\",\"messages\":[\{\"role\":\"user\",\"content\":\"hi\"\}]\}"
#     let request = read_request(text).unwrap()
#     if request.model != "example" or request.stream or not request.user.is_none(): return panic("unexpected request")
#     if parse[Request](text: "\{\"model\":1\}").is_ok(): return panic("wrong member type was accepted")
# ```
#
# | JSON | Decoded as |
# | --- | --- |
# | Object | A record, members in any order. An absent member takes the field's default, else `none` for an `Optional` field. An absent required field returns `InvalidData`, so a field with no JSON form needs a default to be readable. A member that is not a field is ignored unless `ignore_unknown_fields: false`, which returns `InvalidData`. |
# | `"Case"` or `{"Case":{"label":value}}` | An alternative case without or with payload, under the same member rules. Another case name, a payload on a case without one, or a missing payload returns `InvalidData`. |
# | `null` | `none` for `Optional`; anything else returns `InvalidData`. |
# | Array | `List`, or `Set` (repeated elements are dropped). |
# | Object | `Map[K, V]` in document order. Member names are converted to `K`; two names that read as one key, such as `"1"` and `"01"`, return `InvalidData`. |
# | Number | `Int` for integer digits within 64 bits (no fraction or exponent); `Float` for any finite number; `BigInt` and `Decimal` read the exact number text; `Duration` reads integer nanoseconds. |
# | String | `String`, `Timestamp` (RFC 3339), `Bytes` (base64), `Url`, `IpAddress` and `Cidr`. |
# | Any value | `JsonValue` keeps the subtree as parsed. |
#
# A value with the wrong JSON type or shape returns `InvalidData`; this release does not report where. `JsonLimits` apply to the document before decoding. `try` gives its operand no expected type, so write `try parse[Request](text)`.
#
# Stringify produces compact JSON unless `indent` is given, and escapes `<`, `>`, and `&` as `\u003c`, `\u003e`, and `\u0026`. It is not a canonical format for signing.
#
# ## YAML behavior
#
# The parser is written in Manuscript. It reads one YAML 1.2 configuration document with textual mapping keys, block and flow collections, compact sequences and mappings, comments, quoted strings and Unicode escapes, continued scalars, and literal/folded block scalars with indentation and chomping indicators. It accepts a BOM, normalized line endings, document markers, and the `%YAML 1.2` directive.
#
# `YamlValue` represents null, booleans, exact number text, strings, lists, and insertion-ordered maps. Core-schema booleans include `true` and `false` with YAML capitalization; `yes`, `no`, and dates remain strings. Plain mapping keys retain their text; quoted keys are decoded before duplicate checking.
#
# Anchors and previously defined aliases retain the same value references. Forward and recursive aliases fail. Merge keys accept a mapping or a list of mappings; earlier mappings win and explicit entries override merged values. Duplicate explicit keys fail.
#
# Continued plain and quoted scalars fold adjacent lines to a space and retain one newline per intervening blank line. Quoted folding discards surrounding physical whitespace; double-quoted escaped continuations discard the first break while preserving preceding content whitespace. Folded blocks (`>`) use the same paragraph rule between ordinary lines and preserve breaks around more-indented content. Literal blocks (`|`) retain their line breaks. Block chomping controls final breaks, including trailing blank lines; a missing final line ending is not added.
#
# This configuration parser does not implement the complete YAML specification: explicit tags, complex/explicit mapping keys, custom directives, multiple documents, and flow sequence mapping shorthand are unsupported. Specialized flow indentation rules are not fully implemented. `UnsupportedFeature` identifies explicit tags, complex keys, and unsupported directives; other malformed or unsupported forms return `InvalidData` with a one-based line, column, and reason. Positions identify the offending token: merge-key errors point at the `<<` key and block-scalar header errors at the offending header character.
#
# ## TOML behavior
#
# The parser is written in Manuscript and targets TOML 1.0. The result is a `TableValue`, including for an empty document. Values include strings, signed 64-bit integers, binary64 floats, booleans, date/time token text, lists, and insertion-ordered tables.
#
# It supports bare/quoted/dotted keys, explicit and implicit tables, arrays of tables, heterogeneous arrays, closed inline tables, comments, literal/basic strings, multiline strings, Unicode escapes, and escaped newline folding. Integers support decimal, hexadecimal, octal, and binary forms with valid underscore separators; floats include exponents, infinities, and NaN. Date/time values preserve their spelling and fractional precision after checking calendar/time fields. No host timezone conversion occurs.
#
# Duplicate keys, table redefinitions, scalar/table conflicts, extensions to closed inline tables, malformed strings/numbers/dates, out-of-range integers, trailing text, and bare carriage returns fail with `InvalidData(line, column, reason)`. CRLF becomes LF. Control characters and bare carriage returns report their own line and column, and a bad bare value (such as `True` or `yes`) reports `invalid value` at the token start. Dates allow leap-second spelling (`60`) without checking a historical leap-second registry. Binary64 conversion rejects overflowing finite float tokens. TOML 1.1 extensions are outside this parser's contract.
#
# ## YAML and TOML limits
#
# `YamlLimits` and `TomlLimits` each contain `max_bytes`, `max_depth`, and `max_values`, all `Optional[Int]`. Their ordinary record constructors require all three fields; use `none` for each omitted budget. Omitting `limits` or passing `none` adds no cap.
#
# - `max_bytes` counts UTF-8 input bytes before normalization.
# - `max_depth` counts every value level, with the root at one, including scalar leaves and implicit TOML tables.
# - `max_values` counts containers and leaves, excluding keys. YAML checks both parsed values and the returned tree with aliases counted at each occurrence; merge-source values also consume the parsing budget.
#
# Negative limits return `InvalidInput`; zero is a real budget and exhaustion returns `LimitExceeded`. Empty YAML still returns one null value; empty TOML returns one table. Limits are checked during parsing and against the completed result. Input text and the parser's character/line lists are already allocated; these budgets do not provide a general memory or CPU sandbox. With no budgets, YAML aliases are returned without traversing their expanded tree.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {parse, TomlValue, TomlLimits} from "@std/toml.ms"
# import panic from "@std/faults.ms"
#
# test "parse bounded TOML configuration":
#     let limits = TomlLimits(max_bytes: 1024, max_depth: 8, max_values: 64)
#     let value = match parse(text: "[server]\nport = 8080\n", limits: limits):
#         error(cause): return panic(cause.message())
#         ok(value): value
#
#     match value:
#         TableValue(entries):
#             if not entries.contains("server"): return panic("missing server table")
#         _: return panic("expected table")
#
# ```
#
# ## CSV behavior
#
# `CsvOptions()` creates fresh mutable options with `delimiter: ","` and `line_ending: "\n"`. `parse(text: "a,b\n")` and `stringify(rows: [["a", "b"]])` use these defaults. Either option field can be supplied independently; use `CsvOptions(line_ending: "\r\n")` for CRLF output. Explicit options retain their values and are validated as usual.
#
# The delimiter must be one non-NUL ASCII byte other than quote, CR, or LF. `line_ending` is LF or CRLF. Row, cell, and output limits must be nonnegative; `max_cells` counts every returned cell.
#
# CSV quotes are doubled; values are not trimmed or converted to other types, rows may have different widths, and blank lines are ignored. CRLF is normalized, including inside quoted cells. Serialization ends every row with the selected terminator. Formula-like spreadsheet values are left as supplied.
#
# A row containing one empty string is serialized as a quoted empty field (`""`), so parsing retains it. A row with no cells is serialized as a blank line and is skipped on parsing; these two rows have distinct serialized forms. Multiple empty cells retain their delimiters.
#
# Exceeded limits return `LimitExceeded`. The input String is already in memory, and the parser reads one record before checking its row and cell limits. Bound the source read before parsing untrusted CSV.
#
# ## URL behavior
#
# `parse` requires an absolute hierarchical URL and rejects user information. Scheme and host become lowercase. The optional port is in the range 0–65535.
#
# The path keeps escaped separators, the query stays encoded, and the fragment is decoded. Resolving a relative URL merges it with the base path and removes dot segments. `Url` is an ordinary record, so `format` and `resolve` validate values constructed by application code too. Unsupported opaque URLs return `InvalidData`.
#
# Query entries retain duplicates and order. Empty segments, as in `a=1&&b=2` or a trailing `&`, are skipped and do not count toward `max_entries`. A bare key has an empty value; `+` represents a space. Component encoding preserves only ASCII unreserved characters. Decoding rejects invalid UTF-8.
#
# Hostnames are not normalized through IDNA; absent and empty queries have the same representation.
#
# ## HTML parsing and text conversion
#
# `parse` returns an `HtmlNode.Document` containing an HTML5 tree. Match `Element` to work with its tag, namespace, ordered `List[HtmlAttribute]`, and child nodes. `Text`, `Comment`, and `Doctype` preserve their data. These are ordinary Manuscript data values; child lists and attribute records are mutable.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {parse, HtmlNode} from "@std/html.ms"
# import panic from "@std/faults.ms"
#
# fn text_content(node: HtmlNode) -> String:
#     match node:
#         Text(text): return text
#         Document(children):
#             var text = ""
#             for child in children: text = "{text}{text_content(child)}"
#             return text
#         Element(_, _, _, children):
#             var text = ""
#             for child in children: text = "{text}{text_content(child)}"
#             return text
#         _: return ""
#
# fn read_text() -> Result[String, Error]:
#     let document = try parse(text: "<p>Hello <b>world</b> &amp; friends</p>")
#     return ok(text_content(document))
#
# test "read HTML text":
#     match read_text():
#         ok(text):
#             if text != "Hello world & friends": return panic("unexpected text")
#         error(cause): return panic(cause.message())
# ```
#
# Parsing follows HTML5 document rules: omitted `html`, `head`, `body`, and table structure are inserted, ordinary HTML names become lowercase, and incomplete or misnested markup is recovered. A snippet is parsed as a document, rather than in a supplied fragment context. Text and attribute entities are decoded; raw script/style text follows HTML5 rules. Attribute order is preserved, including duplicate attributes retained by the parser. HTML namespaces are empty; foreign elements use `svg` or `math`, and namespaced attributes use prefixes such as `xlink`. A doctype's absent public/system identifiers are empty strings. Scripts are retained as text and never executed.
#
# `HtmlLimits` fields are optional and nonnegative:
#
# | Limit | What it counts |
# | --- | --- |
# | `max_bytes` | UTF-8 input bytes, checked before parsing. |
# | `max_depth` | Returned node depth; the document is depth zero. |
# | `max_nodes` | All returned nodes, including the document, text, comments, doctypes, and inserted elements. Attributes are excluded. |
#
# Omitted limits impose no added cap. An empty input produces four nodes (`Document`, `html`, `head`, and `body`) with maximum depth two. Depth and node budgets are checked while converting the native tree, after HTML5 parsing has allocated it; use a byte budget to bound the input first. Negative limits return `HtmlError.InvalidInput`, invalid UTF-8 or a native parser failure returns `InvalidData`, and exceeded budgets return `LimitExceeded`. Recoverable markup errors are accepted.
#
# `escape` handles text and quoted attribute contexts. It does not sanitize HTML or escape script, stylesheet, or URL content.
#
# `unescape(text:) -> String` decodes HTML5 character references in text context, in one pass. Named references such as `&lt;`, decimal references such as `&#225;`, and hexadecimal references such as `&#xE1;` are recognized. HTML5 text rules accept some references without semicolons and select recognized prefixes; `unescape("&ampx")` returns `"&x"`. Unrecognized text such as `&bogus;` remains literal. Invalid numeric scalars (zero, surrogates, and values above U+10FFFF) become U+FFFD, and the HTML5 C1 replacement table applies to numeric references.
#
# The output is ordinary immutable String, without markup parsing or Unicode normalization. Decoded text is not decoded again: `unescape("&amp;lt;")` is `"&lt;"`. `unescape(escape(text))` preserves `text`, while escaping an unescaped reference may choose another equivalent spelling. Attribute parsing has its own HTML5 reference rules; use `parse` to obtain decoded attributes from markup. Cancellation is checked before and after this atomic text codec and may wait for the codec to return.
# end-documentation
