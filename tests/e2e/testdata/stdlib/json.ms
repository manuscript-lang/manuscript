import {
    parse,
    stringify,
    JsonValue,
    JsonLimits,
    JsonError
} from "@std/json.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "JSON exact numbers Unicode and nested roundtrip":
    let text = "\{\"n\":9007199254740993,\"s\":\"é🙂\",\"a\":[null,true,false]\}"
    let parsed = value(parse(text: text))
    if value(stringify(value: parsed)) != text: return panic("JSON precision or order")
    if value(parse(text: "\"\\uD83D\\uDE00\"")) != JsonValue.StringValue("😀"): return panic(
        "surrogate pair"
    )
    if (
        value(
            stringify(
                value: value(parse(text: "null")),
                max_bytes: 4
            )
        ) != "null"
    ): return panic("exact budget")

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
    if (
        parse(
            text: "null",
            limits: JsonLimits(max_bytes: 3)
        ) != limited
    ): return panic("JSON byte budget")
    if (
        parse(
            text: "[[[]]]",
            limits: JsonLimits(max_depth: 2)
        ) != limited
    ): return panic("JSON depth budget")
    if (
        parse(
            text: "[1,2]",
            limits: JsonLimits(max_values: 2)
        ) != limited
    ): return panic("JSON value budget")

    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidInput)
    if (
        parse(
            text: "null",
            limits: JsonLimits(max_bytes: -1)
        ) != invalid
    ): return panic("negative JSON budget")
