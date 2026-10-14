import {
    parse,
    stringify,
    JsonValue,
    JsonLimits,
    JsonError,
    JsonEncodable
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

type Request:
    model: String
    stream: Bool
    user: Optional[String]
    temperature: Float
    tags: List[String]

type Shape:
    case Circle(radius: Int)
    case Rect(width: Int, height: Int)
    case Dot

type Scene:
    shape: Shape
    shapes: List[Shape]
    note: Optional[String]

type Box[T]:
    first: T
    second: Optional[T]

type Node:
    label: String
    next: Optional[Node]

fn encoded[T: JsonEncodable](item: T) -> String:
    return value(stringify(value: item))

test "JSON stringify encodes records in declaration order and omits none fields":
    let request = Request(
        model: "m",
        stream: true,
        user: none,
        temperature: 0.5,
        tags: ["a", "b"]
    )
    let expected = "\{\"model\":\"m\",\"stream\":true,\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    if encoded(request) != expected: return panic("record order or omitted none field")

    request.user = some("u")
    let named = "\{\"model\":\"m\",\"stream\":true,\"user\":\"u\",\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    if encoded(request) != named: return panic("present optional field")
    if encoded(Box[Int](first: 1, second: none)) != "\{\"first\":1\}": return panic(
        "generic record order"
    )
    if encoded(Box[Int](first: 1, second: some(2))) != "\{\"first\":1,\"second\":2\}": return panic(
        "generic optional field"
    )

test "JSON stringify encodes alternatives and nested optionals":
    let scene = Scene(
        shape: Shape.Circle(2),
        shapes: [Shape.Dot, Shape.Rect(1, 2)],
        note: none
    )
    let expected = "\{\"shape\":\{\"Circle\":\{\"radius\":2\}\},\"shapes\":[\"Dot\",\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
    if encoded(scene) != expected: return panic("alternative encoding")

    let sparse: List[Optional[Int]] = [some(1), none]
    if encoded(sparse) != "[1,null]": return panic("none inside a list is null")

    let missing: Optional[Int] = none
    if encoded(missing) != "null": return panic("root none is null")

test "JSON stringify keeps map insertion order and encodes scalars exactly":
    let ordered = Map[String, Int]().add("b", 2).add("a", 1)
    if encoded(ordered) != "\{\"b\":2,\"a\":1\}": return panic("map insertion order")
    if encoded(9007199254740993) != "9007199254740993": return panic("large Int")
    if encoded(1.0) != "1": return panic("whole Float")
    if encoded(0.1) != "0.1": return panic("shortest Float")
    if encoded(1e300) != "1e+300": return panic("exponent Float")
    if encoded("<é\n") != "\"\\u003cé\\n\"": return panic("string escaping")

    let parsed = value(parse(text: "\{\"n\":1.50\}"))
    let mixed = Box[JsonValue](first: parsed, second: none)
    if encoded(mixed) != "\{\"first\":\{\"n\":1.50\}\}": return panic(
        "JsonValue passthrough"
    )

test "JSON stringify reports cycles non-finite numbers and budgets as errors":
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    var node = Node(label: "a", next: none)
    node.next = some(node)
    if stringify(value: node) != invalid: return panic("cyclic record")
    if stringify(value: 1e308 * 10.0) != invalid: return panic("infinite Float")

    let limited: Result[String, JsonError] = error(JsonError.LimitExceeded)
    if stringify(value: "abcdef", max_bytes: 4) != limited: return panic(
        "output budget"
    )

    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    if stringify(value: 1, max_bytes: -1) != negative: return panic("negative budget")

test "JSON stringify repeats shared acyclic values and reads current field values":
    let shared = Node(label: "s", next: none)
    let pair = [shared, shared]
    let before = encoded(pair)
    shared.label = "changed"
    if before != "[\{\"label\":\"s\"\},\{\"label\":\"s\"\}]": return panic(
        "shared value written twice"
    )
    if encoded(pair) == before: return panic("stringify reads current field values")
