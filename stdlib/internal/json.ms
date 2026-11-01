import JsonError, JsonLimits from "@std/data/json.ms"

# The compiler lowers these two calls from the type argument; see `json_parse` and `json_stringify` in ms-lower.
export extern fn msstd_json_parse[T](
    text: String,
    limits: JsonLimits?,
    ignore_unknown_fields: Bool
) T!JsonError

export extern fn msstd_json_stringify[T](
    value: T,
    max_bytes: Int?,
    indent: Int?,
    strict: Bool
) String!JsonError
