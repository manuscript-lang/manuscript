# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Result from "@std/result.ms"

export type JsonLimits:
    max_bytes: Int
    max_depth: Int
    max_values: Int

export type JsonValue:
    case Null
    case BoolValue(value: Bool)
    case NumberValue(text: String)
    case StringValue(value: String)
    case ArrayValue(values: List[JsonValue])
    case ObjectValue(values: Map[String, JsonValue])

export fn parse(text: String, limits: JsonLimits) -> Result[JsonValue, LibraryError]

export fn stringify(value: JsonValue, max_bytes: Int) -> Result[String, LibraryError]
