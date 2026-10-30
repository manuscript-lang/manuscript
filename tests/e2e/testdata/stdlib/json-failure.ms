import parse, JsonValue, JsonError, JsonLimits from "@std/json.ms"
import expect_equal from "@std/test.ms"

test "JSON syntax errors keep their identity with unread Unicode suffixes":
    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    let typed_invalid: Result[String, JsonError] = error(JsonError.InvalidData)

    for text in [
        "]plain", "]\\\\", "]\"\\u0041\"", "]\"\\uD800\"", "]\"\\u12",
        "true x\"\\uD800\""
    ]:
        try expect_equal(parse(text), invalid)
        try expect_equal(parse[String](text), typed_invalid)

test "JSON value limits preserve Unicode precedence and byte admission":
    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    let typed_invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    let typed_limited: Result[String, JsonError] = error(JsonError.LimitExceeded)
    let zero = JsonLimits(max_values: 0)

    for text in ["\"\\uD800\"", "\"\\uDC00\"", "\"\\u12"]:
        try expect_equal(parse(text, zero), invalid)
        try expect_equal(parse[String](text, zero), typed_invalid)

    try expect_equal(parse("\"\\u0041\"", zero), limited)
    try expect_equal(parse[String]("\"\\u0041\"", zero), typed_limited)
    try expect_equal(parse("\"\\uD800\"", JsonLimits(max_bytes: 0)), limited)
    try expect_equal(
        parse[String]("\"\\uD800\"", JsonLimits(max_bytes: 0)), typed_limited
    )

    let negative: Result[JsonValue, JsonError] = error(JsonError.InvalidInput)
    let typed_negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    try expect_equal(parse("\"\\uD800\"", JsonLimits(max_values: -1)), negative)
    try expect_equal(
        parse[String]("\"\\uD800\"", JsonLimits(max_values: -1)), typed_negative
    )
