# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"

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
export fn parse(
    text: String,
    limits: Optional[JsonLimits] = none
) -> Result[JsonValue, JsonError]:

# Bound satisfied by every type that `stringify` can encode: Bool, Int, Float, String, Decimal and
# BigInt; JsonValue; Optional, List and Set of encodable types; Map with String keys and encodable
# values; and records or alternatives whose fields are all encodable. Functions, interfaces, resources,
# Bytes, time values, Unit, Result and other standard-library types do not satisfy it. The compiler
# derives the property from the type's shape, so it cannot be implemented or overridden.
export type JsonEncodable:

# Encodes any value whose type satisfies JsonEncodable as compact JSON text.
#
# - Record fields appear in declaration order. A field of type `Optional[T]` is omitted when `none`.
# - Any other `none` (a list element, a map value, the root) is `null`; `Optional[Optional[T]]` is rejected.
# - An alternative case without payload is its name as a string, `"Circle"`. A case with payload is an
#   object keyed by the case name whose value is an object of its labeled fields: `{"Circle":{"radius":2}}`.
# - Map entries and Set elements keep insertion order; maps must have String keys.
# - Int, BigInt and Decimal are written as exact decimal digits; Float uses the shortest decimal that
#   parses back to the same value, and NaN or an infinity returns InvalidData.
# - A JsonValue is written as it is, so parsed documents can be mixed with typed data.
# - Strings are UTF-8 JSON strings; `<`, `>` and `&` are written as Unicode escapes.
# - Values are read when `stringify` runs, so later mutation does not change the text. A value reachable
#   from itself returns InvalidData; shared but acyclic values are written each time they appear.
#
# `max_bytes` bounds the output; exceeding it returns LimitExceeded and a negative bound InvalidInput.
#
# ```manuscript
# type Request:
#     model: String
#     stream: Bool
#     user: Optional[String]
#
# stringify(value: Request(model: "example", stream: true, user: none))
# ```
export fn stringify[T: JsonEncodable](
    value: T,
    max_bytes: Optional[Int] = none
) -> Result[String, JsonError]:

impl Error for JsonError:
    # Returns a JSON-prefixed diagnostic without echoing input text or number tokens.
    fn message() -> String:
