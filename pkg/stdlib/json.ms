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

# Serializes a JSON value. `max_bytes` bounds output when supplied.
export fn stringify(
    value: JsonValue,
    max_bytes: Optional[Int] = none
) -> Result[String, JsonError]:

# Wraps text as a JSON string value.
export fn from_string(value: String) -> JsonValue:

# Wraps a Bool as a JSON boolean value.
export fn from_bool(value: Bool) -> JsonValue:

# Wraps an Int as a JSON number using its exact decimal digits.
export fn from_int(value: Int) -> JsonValue:

# Wraps a finite Float as a JSON number. NaN and infinities return `InvalidData`.
export fn from_float(value: Float) -> Result[JsonValue, JsonError]:

# Validates JSON number text and keeps its exact spelling, such as `9007199254740993`.
# Malformed text and text for any other JSON value return `InvalidData`.
export fn from_number(text: String) -> Result[JsonValue, JsonError]:

# Builds an array from a shallow copy of `values`; later list changes do not affect it.
export fn array(values: List[JsonValue]) -> JsonValue:

# Builds an object from a shallow copy of `fields`, keeping insertion order. A map
# already has unique keys, so duplicates cannot occur; a literal with an equal key
# keeps the first position and the last value.
export fn object(fields: Map[String, JsonValue]) -> JsonValue:

# Builds an object from the present entries; a `none` value omits its key. Entries
# keep their insertion order.
export fn object_optional(fields: Map[String, Optional[JsonValue]]) -> JsonValue:

impl Error for JsonError:
    # Returns a JSON-prefixed diagnostic without echoing input text or number tokens.
    fn message() -> String:
