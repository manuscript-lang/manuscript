import {expect_equal, expect_not_equal, expect_ok, fail} from "@std/testing.ms"
import {decoder, JsonDecoder} from "@std/jsonstream.ms"
import {stringify, JsonValue, JsonLimits, JsonError} from "@std/json.ms"
import Bytes from "@std/bytes.ms"

fn texts(values: List[JsonValue]) -> Result[List[String], Error]:
    let result: List[String] = []
    for item in values:
        result.append((stringify(item) | try expect_ok))
    return ok(result)

# Feeds the input in chunks of `size` bytes and returns every decoded value as text.
fn decode(input: Bytes, size: Int) -> Result[List[String], Error]:
    let reader = (decoder() | try expect_ok)
    let result: List[String] = []
    var offset = 0

    while offset < input.length():
        var end = offset + size
        if end > input.length(): end = input.length()
        for text in (
            try texts(
                (
                    reader.feed(
                        (
                            input.slice(
                                offset,
                                end
                            ) | try expect_ok
                        )
                    ) | try expect_ok
                )
            )
        ):
            result.append(text)
        offset = end

    for text in (try texts((reader.finish() | try expect_ok))):
        result.append(text)
    return ok(result)

test "JSON decoder preserves values split at every chunk size":
    let source = "\{\"a\":\"é🙂\\u00e9\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}\n\"s\"[1]\{\"b\":2\}  42"
    let expected = [
        "\{\"a\":\"é🙂é\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}",
        "\"s\"", "[1]", "\{\"b\":2\}", "42"
    ]
    let input = source.to_bytes()
    var size = 1

    while size <= input.length():
        if (try decode(input, size)) != expected: return fail("chunk size {size}")

        size = size + 1

test "JSON decoder reports truncated and malformed input":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)

    for text in ["\{\"a\":[1", "\"open", "x", "[1]]", "truex y"]:
        let reader = (decoder() | try expect_ok)
        let fed = reader.feed("{text} ".to_bytes())

        if text == "\{\"a\":[1" or text == "\"open":
            if reader.finish() != invalid: return fail("truncated {text}")
        else if fed != invalid and reader.finish() != invalid: return fail(
            "malformed {text}"
        )

test "JSON decoder rejects invalid UTF-8 and stays failed":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)
    let closed: Result[List[JsonValue], JsonError] = error(JsonError.InvalidInput)
    let reader = (decoder() | try expect_ok)
    let bad = "\"a\"".to_bytes()
    reader.feed(bad.with_value(1, 255)) | try expect_equal(expected: invalid)
    reader.feed("1 ".to_bytes()) | try expect_equal(expected: invalid)
    let ended = (decoder() | try expect_ok)
    let checked_82 = (ended.finish() | try expect_ok)
    ended.feed("1 ".to_bytes()) | try expect_equal(expected: closed)
    ended.finish() | try expect_equal(expected: closed)

test "JSON decoder applies per-value budgets":
    let limited: Result[List[JsonValue], JsonError] = error(JsonError.LimitExceeded)
    let bytes = (decoder(JsonLimits(max_bytes: 5)) | try expect_ok)
    bytes.feed("[1,2]".to_bytes()) | try expect_not_equal(expected: limited)
    bytes.feed("[1,2,3]".to_bytes()) | try expect_equal(expected: limited)
    let depth = (decoder(JsonLimits(max_depth: 2)) | try expect_ok)
    depth.feed("[[[".to_bytes()) | try expect_equal(expected: limited)

    match decoder(JsonLimits(max_values: -1)):
        error(cause):
            try expect_equal(cause, JsonError.InvalidInput)
        ok(_): return fail("negative limit accepted")
