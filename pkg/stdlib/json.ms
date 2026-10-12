# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Result from "@std/result.ms"

export type JsonError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export type JsonLimits:
    max_bytes: Optional[Int] = none
    max_depth: Optional[Int] = none
    max_values: Optional[Int] = none

export type JsonValue:
    case Null
    case BoolValue(value: Bool)
    case NumberValue(text: String)
    case StringValue(value: String)
    case ArrayValue(values: List[JsonValue])
    case ObjectValue(values: Map[String, JsonValue])

export fn parse(text: String, limits: Optional[JsonLimits] = none) -> Result[JsonValue, JsonError]

export fn stringify(value: JsonValue, max_bytes: Optional[Int] = none) -> Result[String, JsonError]

impl Error for JsonError:
    fn message() -> String
