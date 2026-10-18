import {decoder} from "@std/jsonstream.ms"
import {stringify, JsonValue, JsonLimits, JsonError} from "@std/json.ms"
import Bytes from "@std/bytes.ms"
import range from "@std/collections.ms"
import panic from "@std/faults.ms"

fn texts(values: List[JsonValue]) Result[List[String], Error]:
    let result: List[String] = []
    for item in values:
        result.append(try stringify(item))
    return ok(result)

# Feeds the input in chunks of `size` bytes and returns every decoded value as text.
fn decode(input: Bytes, size: Int) Result[List[String], Error]:
    let reader = try decoder()
    let result: List[String] = []
    var offset = 0

    while offset < input.length():
        var end = offset + size
        if end > input.length(): end = input.length()
        for text in try texts(try reader.feed(try input.slice(offset, end))):
            result.append(text)
        offset = end

    for text in try texts(try reader.finish()):
        result.append(text)
    return ok(result)

test "JSON decoder preserves values split at every chunk size":
    let source = "\{\"a\":\"é🙂\\u00e9\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}\n\"s\"[1]\{\"b\":2\}  42"
    let expected = [
        "\{\"a\":\"é🙂é\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}",
        "\"s\"", "[1]", "\{\"b\":2\}", "42"
    ]
    let input = source.to_bytes()
    for size in range(1, input.length() + 1):
        if (try decode(input, size)) != expected: return panic("chunk size {size}")

test "JSON decoder reports truncated and malformed input":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)

    for text in ["\{\"a\":[1", "\"open", "x", "[1]]", "truex y"]:
        let reader = try decoder()
        let fed = reader.feed("{text} ".to_bytes())

        if text == "\{\"a\":[1" or text == "\"open":
            if reader.finish() != invalid: return panic("truncated {text}")
        else if fed != invalid and reader.finish() != invalid: return panic(
            "malformed {text}"
        )

test "JSON decoder rejects invalid UTF-8 and stays failed":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)
    let closed: Result[List[JsonValue], JsonError] = error(JsonError.InvalidInput)
    let reader = try decoder()
    let bad = "\"a\"".to_bytes()
    if reader.feed(bad.with_value(1, 255)) != invalid: return panic("invalid UTF-8")
    if reader.feed("1 ".to_bytes()) != invalid: return panic("sticky failure")

    let ended = try decoder()
    let _values = try ended.finish()
    if ended.feed("1 ".to_bytes()) != closed: return panic("feed after finish")
    if ended.finish() != closed: return panic("finish twice")

test "JSON decoder applies per-value budgets":
    let limited: Result[List[JsonValue], JsonError] = error(JsonError.LimitExceeded)
    let bytes = try decoder(JsonLimits(max_bytes: 5))
    if bytes.feed("[1,2]".to_bytes()) == limited: return panic(
        "value at the byte limit"
    )
    if bytes.feed("[1,2,3]".to_bytes()) != limited: return panic("byte limit")

    let depth = try decoder(JsonLimits(max_depth: 2))
    if depth.feed("[[[".to_bytes()) != limited: return panic("depth limit")

    let negative = decoder(JsonLimits(max_values: -1))
    if not negative.is_error(): return panic("negative limit accepted")
    if negative.unwrap_error() != JsonError.InvalidInput: return panic("negative limit")
