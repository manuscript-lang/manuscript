import parse, JsonValue, JsonLimits from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

test "JSON syntax errors keep their identity with unread Unicode suffixes":
    let invalid: JsonValue! = error(
        Error("JSON: invalid data", kind: ErrorCategory.InvalidData)
    )
    let typed_invalid: String! = error(
        Error("JSON: invalid data", kind: ErrorCategory.InvalidData)
    )

    for text in [
        "]plain", "]\\\\", "]\"\\u0041\"", "]\"\\uD800\"", "]\"\\u12",
        "true x\"\\uD800\""
    ]:
        try expect_equal(parse(text), invalid)
        try expect_equal(parse[String](text), typed_invalid)

test "JSON value limits preserve Unicode precedence and byte admission":
    let invalid: JsonValue! = error(
        Error("JSON: invalid data", kind: ErrorCategory.InvalidData)
    )
    let typed_invalid: String! = error(
        Error("JSON: invalid data", kind: ErrorCategory.InvalidData)
    )
    let limited: JsonValue! = error(
        Error("JSON: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    let typed_limited: String! = error(
        Error("JSON: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
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

    let negative: JsonValue! = error(
        Error("JSON: invalid input", kind: ErrorCategory.InvalidInput)
    )
    let typed_negative: String! = error(
        Error("JSON: invalid input", kind: ErrorCategory.InvalidInput)
    )
    try expect_equal(parse("\"\\uD800\"", JsonLimits(max_values: -1)), negative)
    try expect_equal(
        parse[String]("\"\\uD800\"", JsonLimits(max_values: -1)), typed_negative
    )
