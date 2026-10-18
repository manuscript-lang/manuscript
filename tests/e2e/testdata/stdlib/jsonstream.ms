import {decoder, JsonDecoder} from "@std/jsonstream.ms"
import {stringify, JsonValue, JsonLimits, JsonError} from "@std/json.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn texts(values: List[JsonValue]) List[String]:
    let result: List[String] = []
    for item in values:
        result.append(value(stringify(item)))
    return result

# Feeds the input in chunks of `size` bytes and returns every decoded value as text.
fn decode(input: Bytes, size: Int) List[String]:
    let reader = value(decoder())
    let result: List[String] = []
    var offset = 0

    while offset < input.length():
        var end = offset + size
        if end > input.length(): end = input.length()
        for text in texts(value(reader.feed(value(input.slice(offset, end))))):
            result.append(text)
        offset = end

    for text in texts(value(reader.finish())):
        result.append(text)
    return result

test "JSON decoder preserves values split at every chunk size":
    let source = "\{\"a\":\"é🙂\\u00e9\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}\n\"s\"[1]\{\"b\":2\}  42"
    let expected = [
        "\{\"a\":\"é🙂é\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}",
        "\"s\"", "[1]", "\{\"b\":2\}", "42"
    ]
    let input = source.to_bytes()
    var size = 1

    while size <= input.length():
        if decode(input, size) != expected: return panic("chunk size {size}")

        size = size + 1

test "JSON decoder reports truncated and malformed input":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)

    for text in ["\{\"a\":[1", "\"open", "x", "[1]]", "truex y"]:
        let reader = value(decoder())
        let fed = reader.feed("{text} ".to_bytes())

        if text == "\{\"a\":[1" or text == "\"open":
            if reader.finish() != invalid: return panic("truncated {text}")
        else if fed != invalid and reader.finish() != invalid: return panic(
            "malformed {text}"
        )

test "JSON decoder rejects invalid UTF-8 and stays failed":
    let invalid: Result[List[JsonValue], JsonError] = error(JsonError.InvalidData)
    let closed: Result[List[JsonValue], JsonError] = error(JsonError.InvalidInput)
    let reader = value(decoder())
    let bad = "\"a\"".to_bytes()
    if reader.feed(bad.with_value(1, 255)) != invalid: return panic("invalid UTF-8")
    if reader.feed("1 ".to_bytes()) != invalid: return panic("sticky failure")

    let ended = value(decoder())
    value(ended.finish())
    if ended.feed("1 ".to_bytes()) != closed: return panic("feed after finish")
    if ended.finish() != closed: return panic("finish twice")

test "JSON decoder applies per-value budgets":
    let limited: Result[List[JsonValue], JsonError] = error(JsonError.LimitExceeded)
    let bytes = value(decoder(JsonLimits(max_bytes: 5)))
    if bytes.feed("[1,2]".to_bytes()) == limited: return panic(
        "value at the byte limit"
    )
    if bytes.feed("[1,2,3]".to_bytes()) != limited: return panic("byte limit")

    let depth = value(decoder(JsonLimits(max_depth: 2)))
    if depth.feed("[[[".to_bytes()) != limited: return panic("depth limit")

    match decoder(JsonLimits(max_values: -1)):
        error(cause):
            if cause != JsonError.InvalidInput: return panic("negative limit")
        ok(_): return panic("negative limit accepted")
