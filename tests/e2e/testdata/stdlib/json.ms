import {
    parse,
    stringify,
    JsonValue,
    JsonLimits,
    JsonError,
    from_string,
    from_bool,
    from_int,
    from_float,
    from_number,
    array,
    object,
    object_optional
} from "@std/json.ms"
import {List, Map} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "JSON exact numbers Unicode and nested roundtrip":
    let text = "\{\"n\":9007199254740993,\"s\":\"é🙂\",\"a\":[null,true,false]\}"
    let parsed = value(parse(text: text))
    if value(stringify(value: parsed)) != text: return panic("JSON precision or order")
    if value(parse(text: "\"\\uD83D\\uDE00\"")) != JsonValue.StringValue("😀"): return panic(
        "surrogate pair"
    )
    if (value(stringify(value: value(parse(text: "null")), max_bytes: 4)) != "null"): return panic(
        "exact budget"
    )

test "JSON rejects duplicate keys malformed Unicode and trailing values":
    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidData)

    for text in [
        "\{\"a\":1,\"\\u0061\":2\}",
        "\"\\uD800\"",
        "\"\\uDC00\"",
        "1 2",
        "NaN",
        "[1,]"
    ]:
        if parse(text: text) != invalid: return panic("malformed JSON accepted")

test "JSON independently enforces byte depth and value budgets":
    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    if (parse(text: "null", limits: JsonLimits(max_bytes: 3)) != limited): return panic(
        "JSON byte budget"
    )
    if (parse(text: "[[[]]]", limits: JsonLimits(max_depth: 2)) != limited): return panic(
        "JSON depth budget"
    )
    if (parse(text: "[1,2]", limits: JsonLimits(max_values: 2)) != limited): return panic(
        "JSON value budget"
    )

    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidInput)
    if (parse(text: "null", limits: JsonLimits(max_bytes: -1)) != invalid): return panic(
        "negative JSON budget"
    )

test "JSON stringify rejects number text with trailing whitespace":
    let padded: Result[String, JsonError] = error(JsonError.InvalidData)
    if stringify(value: JsonValue.NumberValue("1\n")) != padded: return panic(
        "trailing newline"
    )
    if stringify(value: JsonValue.NumberValue("1 ")) != padded: return panic(
        "trailing space"
    )

test "JSON parse bounds nesting even without a depth limit":
    var text = ""
    var closing = ""
    var i = 0

    while i < 150000:
        text = text + "["
        closing = closing + "]"
        i = i + 1

    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    if parse(text: text + closing) != limited: return panic("unbounded nesting")

test "JSON builders construct ordered typed values":
    let built = object(
        fields: {
            "model": from_string(value: "example"),
            "stream": from_bool(value: true),
            "tokens": from_int(value: 9007199254740993),
            "tags": array(values: [from_string(value: "a"), JsonValue.Null])
        }
    )
    let expected = "\{\"model\":\"example\",\"stream\":true,\"tokens\":9007199254740993,\"tags\":[\"a\",null]\}"
    if value(stringify(value: built)) != expected: return panic("JSON builder output")

test "JSON builders validate numbers and omit absent fields":
    let invalid: Result[JsonValue, JsonError] = error(cause: JsonError.InvalidData)
    if from_number(text: "01") != invalid: return panic("leading zero number")
    if from_number(text: "true") != invalid: return panic("non-number text")
    if from_float(value: 1.0 / 0.0) != invalid: return panic("infinite float")
    if value(from_number(text: "1e400")) != JsonValue.NumberValue(text: "1e400"): return panic(
        "exact number text"
    )

    let sparse: Map[String, Optional[JsonValue]] = {
        "a": some(value: JsonValue.Null),
        "b": none,
        "c": some(value: from_bool(value: false))
    }
    if (
        value(
            stringify(value: object_optional(fields: sparse))
        ) != "\{\"a\":null,\"c\":false\}"
    ): return panic(
        "optional omission"
    )

test "JSON builders copy their arguments":
    let items: List[JsonValue] = [JsonValue.Null]
    let fields: Map[String, JsonValue] = {"a": JsonValue.Null}
    let list = array(values: items)
    let record = object(fields: fields)
    items.append(JsonValue.Null)
    fields.add(key: "b", value: JsonValue.Null)
    if value(stringify(value: list)) != "[null]": return panic("array aliased")
    if value(stringify(value: record)) != "\{\"a\":null\}": return panic(
        "object aliased"
    )

    let duplicate = object(
        fields: {
            "k": from_int(value: 1),
            "j": JsonValue.Null,
            "k": from_int(value: 2)
        }
    )
    if value(stringify(value: duplicate)) != "\{\"k\":2,\"j\":null\}": return panic(
        "duplicate key order"
    )
