import expect_equal, expect_false, expect_not_equal, fail from "@std/test.ms"
import decoder from "@std/jsonstream.ms"
import stringify, JsonValue, JsonLimits, JsonError from "@std/json.ms"
import Bytes from "@std/bytes.ms"

fn texts(values: List[JsonValue]) Result[List[String], Error]:
    var result: List[String] = []
    for item in values:
        result.append(try stringify(item))
    return ok(result)

# Feeds the input in chunks of `size` bytes and returns every decoded value as text.
fn decode(input: Bytes, size: Int) Result[List[String], Error]:
    var reader = try decoder()
    var result: List[String] = []
    var offset = 0

    while offset < input.length():
        var end = offset + size
        if end > input.length(): end = input.length()
        for text in try input.slice(offset, end) | try reader.feed | try texts:
            result.append(text)
        offset = end

    for text in try reader.finish() | try texts:
        result.append(text)
    return ok(result)

test "JSON decoder preserves values split at every chunk size":
    let source = "\{\"a\":\"é🙂\\u00e9\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}\n\"s\"[1]\{\"b\":2\}  42"
    let expected = [
        "\{\"a\":\"é🙂é\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}",
        "\"s\"", "[1]", "\{\"b\":2\}", "42"
    ]
    let input = source.to_bytes()
    for size in 1..input.length() + 1:
        if (try decode(input, size)) != expected: return fail("chunk size {size}")

test "JSON decoder reports truncated and malformed input":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)

    for text in ["\{\"a\":[1", "\"open", "x", "[1]]", "truex y"]:
        var reader = try decoder()
        let fed = reader.feed("{text} ".to_bytes())

        if text == "\{\"a\":[1" or text == "\"open":
            if reader.finish() != invalid: return fail("truncated {text}")
        else if fed != invalid and reader.finish() != invalid: return fail(
            "malformed {text}"
        )

test "JSON decoder rejects invalid UTF-8 and stays failed":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)
    let closed: Result[List[JsonValue], JsonError] = error(JsonError.InvalidInput)
    var reader = try decoder()
    let bad = "\"a\"".to_bytes()
    try expect_equal(reader.feed(bad.with_value(1, 255)), invalid)
    try expect_equal(reader.feed("1 ".to_bytes()), invalid)

    var ended = try decoder()
    let _values = try ended.finish()
    try expect_equal(ended.feed("1 ".to_bytes()), closed)
    try expect_equal(ended.finish(), closed)

test "JSON decoder applies per-value budgets":
    let limited: Result[List[JsonValue], JsonError] = error(JsonError.LimitExceeded)
    var bytes = try decoder(JsonLimits(5))
    try expect_not_equal(bytes.feed("[1,2]".to_bytes()), limited)
    try expect_equal(bytes.feed("[1,2,3]".to_bytes()), limited)

    var depth = try decoder(JsonLimits(max_depth: 2))
    try expect_equal(depth.feed("[[[".to_bytes()), limited)

    let negative = decoder(JsonLimits(max_values: -1))
    try expect_false(not negative.is_error())
    try expect_equal(negative.err(), JsonError.InvalidInput)
