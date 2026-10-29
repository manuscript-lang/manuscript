import Data from "@std/core.ms"
import parse_float from "@std/math.ms"

# The compiler lowers these two calls from the type argument; see `json_parse` and `json_stringify` in ms-lower.
extern fn msrt_json_parse[T](
    text: String,
    limits: Optional[JsonLimits],
    ignore_unknown_fields: Bool
) Result[T, JsonError]

extern fn msrt_json_stringify[T](
    value: T,
    max_bytes: Optional[Int],
    indent: Optional[Int],
    strict: Bool
) Result[String, JsonError]

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
#
# `get` and `at` read one level and `as_*` read a scalar or container, each returning `none` on a
# mismatch. `get`, `at`, `as_string`, `as_list` and `as_map` lend the part of the document they
# find, with no copy, so nested reads bind each level with `if let`:
#
# ```manuscript
# if let user = doc.get("user"):
#     if let name = user.get("name"):
#         return name.as_string().get("")
# ```
#
# `get_in` reads a chain of object members in one call and lends the same way:
# `doc.get_in(["user", "name"])`. A lambda owns its result, so `and_then(lambda u: u.get("name"))`
# does not check; use `get_in`, read the levels with `if let`, or take a copy with `.clone()`.
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

# A JSON document is Data even though its objects are maps.
impl Data for JsonValue:

impl JsonValue:
    # Returns the object member for `key`, or `none` for an absent key or a value that is not an object. The result borrows from the receiver.
    fn get(key: String) ref Optional[JsonValue]:
        match self:
            ObjectValue(values): return values.get(key)
            _: return none

    # Returns the value reached by reading each object member of `keys` in turn, or `none` when a
    # member is absent, a value on the way is not an object, or `keys` is empty. The result borrows
    # from the receiver.
    fn get_in(keys: List[String]) ref Optional[JsonValue]:
        return member_path(self, keys, 0)

    # Returns the array element at `index`, counting a negative index from the end. An index out of
    # range, or a value that is not an array, returns `none`. The result borrows from the receiver.
    fn at(index: Int) ref Optional[JsonValue]:
        match self:
            ArrayValue(values):
                if index >= values.length() or index < 0 - values.length(): return none

                return values.get(index)
            _: return none

    # Returns the text of a string value, or `none` for any other value. The result borrows from the receiver.
    fn as_string() ref Optional[String]:
        match self:
            StringValue(value): return value
            _: return none

    # Returns a number value as an Int, or `none` when the value is not a number or its text has a
    # fraction, an exponent, or digits that do not fit in Int.
    fn as_int() Optional[Int]:
        match self:
            NumberValue(text): return text.parse_int()
            _: return none

    # Returns a number value as a Float, or `none` when the value is not a number or its text is not finite.
    fn as_float() Optional[Float]:
        match self:
            NumberValue(text): return parse_float(text).to_optional()
            _: return none

    # Returns a boolean value, or `none` for any other value.
    fn as_bool() Optional[Bool]:
        match self:
            BoolValue(value): return value
            _: return none

    # Returns the elements of an array value, or `none` for any other value. The result borrows from the receiver.
    fn as_list() ref Optional[List[JsonValue]]:
        match self:
            ArrayValue(values): return values
            _: return none

    # Returns the members of an object value, or `none` for any other value. The result borrows from the receiver.
    fn as_map() ref Optional[Map[String, JsonValue]]:
        match self:
            ObjectValue(values): return values
            _: return none

    # Returns True only for the Null case; a missing key or any other value returns False.
    fn is_null() Bool:
        match self:
            Null: return true
            _: return false

# Parses one JSON value and applies the supplied input, depth, and value limits.
#
# With the default `T = JsonValue` the result is the parsed tree. Any other `T` is read from the
# document by the inverse of the `stringify` encoding, so `parse[Request](text)` and `let result: Result[Request, JsonError] = parse(text)`
# return a decoded `Request` in a `Result` (`try` passes no expected type, so write `try parse[Request](text)`). A value whose shape does not match `T` returns
# `InvalidData`; nothing is rejected at compile time, as with `stringify`. Input, depth and value limits
# apply to the document before decoding.
#
# - A record is an object. Members may appear in any order. An absent member takes the field's default,
#   else `none` for an `Optional` field; an absent required field returns `InvalidData`, so a field
#   with no JSON form (a function, say) needs a default to be readable. A member that is not a field
#   is ignored, unless `ignore_unknown_fields` is `False`, which makes it return `InvalidData`.
# - An alternative case without payload is its name as a string; one with payload is externally tagged,
#   `{"Circle":{"radius":2}}`, with the same member rules for the labeled fields. Standard alternatives such
#   as `Result` and the error types follow the same rule, so `{"ok":{"value":5}}` reads as `ok(5)`.
# - `Optional[T]` reads `null` as `none`, so `some(none)`, written as `null`, reads back as `none`. `List` reads an array.
# - A sized integer accepts integer digits within its own range, and `Float32` any finite number that fits it.
# - `Int` accepts integer digits that fit in the platform's Int, `Float` any finite number, `BigInt` and `Decimal`
#   the exact number text. A `null` Float, which `stringify` writes for `NaN` and infinities, returns
#   `InvalidData`.
# - `Timestamp` reads an RFC 3339 string, `Duration` integer nanoseconds, `Bytes` a standard base64
#   string, and `Url`, `IpAddress` and `Cidr` their string forms.
# - `JsonValue` keeps its subtree as parsed.
#
# The record-or-document choice comes from `T`, not from the text: `parse[Request]` reads an object as a
# record and `parse[JsonValue]` keeps it as a document.
export fn parse[T: Data = JsonValue](
    text: String,
    limits: Optional[JsonLimits] = none,
    ignore_unknown_fields: Bool = true
) Result[T, JsonError]:
    return msrt_json_parse[T](text, limits, ignore_unknown_fields)

# Customizes how `stringify` encodes a type. It takes precedence over the
# structural encoding for every record and alternative, so it is the way to choose a tagged or
# discriminator encoding, or any other shape. A value whose type implements it is encoded as the
# `JsonValue` its `to_json` returns, wherever it appears: at the root, in a field, in a list, or as a map
# value. The returned `JsonValue` is written as stored and is not customized again. Implement it in the
# module that defines the type. Custom typed decoding is not supported; parse a `JsonValue`
# and handle its cases when the input needs a different shape.
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
#     fn to_json() JsonValue:
#         match self:
#             Created(id): return tagged("created", id)
#             Deleted(id): return tagged("deleted", id)
#
# fn tagged(kind: String, id: Int) JsonValue:
#     var fields = Map[String, JsonValue]()
#     fields.add("type", JsonValue.StringValue(kind))
#     fields.add("id", JsonValue.NumberValue("{id}"))
#     return JsonValue.ObjectValue(fields)
# ```
export interface JsonEncode:
    # Returns the JSON form of this value.
    fn to_json() JsonValue

# Encodes a `Data` value as JSON text; a type that is not `Data` is rejected at compile time.
#
# - Record fields appear in declaration order. A field holding `none` is omitted; so is a field
#   holding a value with no JSON form (`Unit`).
# - `none` elsewhere (a list element, the root) is `null`, as is a no-form list element.
#   `Optional[Optional[T]]` is allowed: `some(none)` is `null` and `none` is omitted.
# - A root value with no JSON form returns `InvalidData`.
# - An alternative case without payload is its name as a string, `"Dot"`. A case with payload is
#   externally tagged: `{"Circle":{"radius":2}}`, an object keyed by the case name whose value holds
#   the labeled fields under the record rules. Payload labels never collide with a discriminator.
# - A `Map` or `Set` is not `Data`; carry an object as a `JsonValue` and a set as a `List`.
# - The sized integers (`Int8` to `Int32`, `UInt8` to `UInt64`) are exact decimal digits, as `Int`.
#   `Float32` is the shortest decimal that reads back as the same `Float32`; NaN and infinities are `null`.
# - Int, BigInt and Decimal are exact decimal digits. Float uses the shortest decimal that parses
#   back to the same value; NaN and infinities are `null`.
# - `Timestamp` is an RFC 3339 string in UTC, `Duration` its integer nanoseconds, `Bytes` a standard
#   base64 string, `Url` its string form, `IpAddress` and `Cidr` their text. `Result`, other standard records and
#   alternatives follow the ordinary rules, so `ok(5)` is `{"ok":{"value":5}}`.
# - A `JsonValue` is written as stored, so parsed documents mix with typed data.
# - A type that implements `JsonEncode` is written as the `JsonValue` its `to_json` returns, instead of any rule above.
# - Strings are UTF-8 JSON strings; only quotes, backslashes and control characters are escaped, so `<`, `>` and `&` stay as written.
# - Values are read when `stringify` runs, so later mutation does not change the text. A value reachable
#   from itself returns `InvalidData`; shared but acyclic values are written each time they appear.
#
# `strict` makes any value without a JSON form, anywhere in the document, return `InvalidData` instead
# of being omitted or written as `null`, so a function, resource, interface value or `Unit` is never
# dropped silently. A field holding `none` is still omitted: that is a value, not a loss.
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
export fn stringify[T: Data](
    value: T,
    max_bytes: Optional[Int] = none,
    indent: Optional[Int] = none,
    strict: Bool = false
) Result[String, JsonError]:
    return msrt_json_stringify(value, max_bytes, indent, strict)

impl Error for JsonError:
    # Returns a JSON-prefixed diagnostic without echoing input text or number tokens.
    fn message() String:
        match self:
            InvalidInput: return "JSON: invalid input"
            InvalidData: return "JSON: invalid data"
            LimitExceeded: return "JSON: limit exceeded"

# The member of `value` at `keys[from:]`, read one object level at a time.
fn member_path(value: JsonValue, keys: List[String], from: Int) ref Optional[JsonValue]:
    if from >= keys.length(): return none
    if from == keys.length() - 1: return value.get(keys[from])
    if let next = value.get(keys[from]):
        return member_path(next, keys, from + 1)

    return none
