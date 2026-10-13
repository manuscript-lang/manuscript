# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"

# Errors returned for malformed JSON or configured input and nesting limits.
export type JsonError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# Optional bounds for JSON input bytes, nesting depth, and parsed values.
export type JsonLimits:
    max_bytes: Optional[Int64] = none
    max_depth: Optional[Int] = none
    max_values: Optional[Int] = none

# A JSON value. Number text is retained to avoid losing precision during parsing.
export type JsonValue:
    case Null
    case BoolValue(value: Bool)
    case NumberValue(text: String)
    case StringValue(value: String)
    case ArrayValue(values: List[JsonValue])
    case ObjectValue(values: Map[String, JsonValue])

# Parses one JSON value and applies the supplied input, depth, and value limits.
export fn parse(
    text: String,
    limits: Optional[JsonLimits] = none
) -> Result[JsonValue, JsonError]:

# Serializes a JSON value. `max_bytes` bounds output when supplied.
export fn stringify(
    value: JsonValue,
    max_bytes: Optional[Int64] = none
) -> Result[String, JsonError]:

impl Error for JsonError:
    fn message() -> String:
