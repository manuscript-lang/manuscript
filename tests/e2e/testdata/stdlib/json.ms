import {
    parse,
    stringify,
    JsonValue,
    JsonLimits,
    JsonError,
    JsonEncode
} from "@std/json.ms"
import {
    timestamp,
    duration,
    clock,
    Timestamp,
    Duration,
    Instant
} from "@std/time.ms"
import {Url} from "@std/url.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import {TextError} from "@std/errors.ms"
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

fn encoded[T](item: T) -> String:
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
    if encoded(1e308 * 10.0) != "null": return panic("infinite Float is null")
    if encoded(1e308 * 10.0 - 1e308 * 10.0) != "null": return panic("NaN Float is null")

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

fn one() -> Int:
    return 1

type Handler:
    name: String
    callback: fn() -> Int
    retries: Optional[Optional[Int]]
    note: Optional[String]

type Money:
    cents: Int

impl JsonEncode for Money:
    fn to_json() -> JsonValue:
        return JsonValue.StringValue("usd:{self.cents}")

type Invoice:
    total: Money
    lines: List[Money]

type Failure:
    cause: Error
    note: String

type Stamped:
    at: Timestamp
    took: Duration
    data: Bytes
    link: Url

type Tagged:
    case Named(name: String, alias: Optional[String])
    case Plain

test "JSON stringify omits values without a JSON form and writes null for list elements":
    let handler = Handler(name: "h", callback: one, retries: none, note: none)
    if encoded(handler) != "\{\"name\":\"h\"\}": return panic(
        "function and none fields omitted"
    )

    handler.retries = some(none)
    if encoded(handler) != "\{\"name\":\"h\",\"retries\":null\}": return panic(
        "some(none) is null"
    )

    handler.retries = some(some(3))
    if encoded(handler) != "\{\"name\":\"h\",\"retries\":3\}": return panic(
        "nested some"
    )

    let callbacks = [one, one]
    if encoded(callbacks) != "[null,null]": return panic("functions in a list are null")

    let named = Map[String, Int]().add("a", 1)
    if encoded(named) != "\{\"a\":1\}": return panic("map")

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    if stringify(value: one) != invalid: return panic("root function has no JSON form")

test "JSON stringify encodes standard-library values":
    let at = value(timestamp(seconds: 1700000000, nanoseconds: 500000000))
    let link = Url(
        scheme: "https",
        host: "example.com",
        port: some(8080),
        path: "/a",
        query: "x=1",
        fragment: ""
    )
    let item = Stamped(at: at, took: duration(1500), data: "hi".to_bytes(), link: link)
    let expected = "\{\"at\":\"2023-11-14T22:13:20.5Z\",\"took\":1500,\"data\":\"aGk=\",\"link\":\"https://example.com:8080/a?x=1\"\}"
    if encoded(item) != expected: return panic("timestamp duration bytes url")

    let failure = Failure(cause: Error(value: TextError.Text("boom")), note: "n")
    if encoded(failure) != "\{\"cause\":\{\"message\":\"boom\"\},\"note\":\"n\"\}": return panic(
        "error message"
    )
    if encoded(TextError.Text("boom")) != "\{\"Text\":\{\"message\":\"boom\"\}\}": return panic(
        "concrete error is structural"
    )

    let ok: Result[Int, Error] = ok(5)
    if encoded(ok) != "\{\"ok\":\{\"value\":5\}\}": return panic("result ok payload")
    if encoded(JsonError.InvalidData) != "\"InvalidData\"": return panic(
        "standard case name"
    )
    if encoded(Tagged.Named("n", none)) != "\{\"Named\":\{\"name\":\"n\"\}\}": return panic(
        "payload case omits none"
    )
    if encoded(Tagged.Plain) != "\"Plain\"": return panic("payloadless case")

test "JSON stringify encodes scalar map keys and rejects the rest":
    let ints = Map[Int, String]().add(2, "b").add(1, "a")
    if encoded(ints) != "\{\"2\":\"b\",\"1\":\"a\"\}": return panic("Int keys")

    let flags = Map[Bool, Int]().add(true, 1)
    if encoded(flags) != "\{\"true\":1\}": return panic("Bool keys")

    let decimals = Map[Decimal, Int]().add(1.50d, 1)
    if encoded(decimals) != "\{\"1.5\":1\}": return panic("Decimal keys")

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    let records = Map[Money, Int]().add(Money(1), 1)
    if stringify(value: records) != invalid: return panic("record keys")

test "JSON stringify honors JsonEncode wherever the value appears":
    let invoice = Invoice(total: Money(500), lines: [Money(200), Money(300)])
    let expected = "\{\"total\":\"usd:500\",\"lines\":[\"usd:200\",\"usd:300\"]\}"
    if encoded(invoice) != expected: return panic("to_json hook")
    if encoded(Money(7)) != "\"usd:7\"": return panic("root hook")

test "JSON stringify indents like JSON.stringify and clamps at ten":
    let request = Request(
        model: "m",
        stream: true,
        user: none,
        temperature: 0.5,
        tags: ["a"]
    )
    let pretty = value(stringify(value: request, indent: 2))
    let expected = "\{\n  \"model\": \"m\",\n  \"stream\": true,\n  \"temperature\": 0.5,\n  \"tags\": [\n    \"a\"\n  ]\n\}"
    if pretty != expected: return panic("indented output")

    let empty: List[Int] = []
    if value(stringify(value: empty, indent: 4)) != "[]": return panic(
        "empty container"
    )
    if value(stringify(value: [1], indent: 0)) != "[1]": return panic(
        "zero indent is compact"
    )

    let wide = value(stringify(value: [1], indent: 99))
    if wide != "[\n          1\n]": return panic("indent clamps at ten")

    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    if stringify(value: 1, indent: -1) != negative: return panic("negative indent")

interface Named:
    fn label() -> String

type Person:
    name: String

impl Named for Person:
    fn label() -> String:
        return self.name

type Holder:
    who: Named
    at: Instant
    done: Unit

test "JSON stringify writes interface values as the value they hold and omits monotonic instants":
    let who = Named(value: Person(name: "p"))
    let holder = Holder(who: who, at: clock().now(), done: unit)
    if encoded(holder) != "\{\"who\":\{\"name\":\"p\"\}\}": return panic(
        "interface field"
    )

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    if stringify(value: clock().now()) != invalid: return panic("root instant")
    if stringify(value: unit) != invalid: return panic("root unit")

    let failed: Result[Int, JsonError] = error(JsonError.LimitExceeded)
    if encoded(failed) != "\{\"error\":\{\"cause\":\"LimitExceeded\"\}\}": return panic(
        "result error payload"
    )

type Event:
    case Created(id: Int)
    case Deleted(id: Int)

impl JsonEncode for Event:
    fn to_json() -> JsonValue:
        match self:
            Created(id): return tagged("created", id)
            Deleted(id): return tagged("deleted", id)

fn tagged(kind: String, id: Int) -> JsonValue:
    let fields = Map[String, JsonValue]().add("type", JsonValue.StringValue(kind))
    let all = fields.add("id", JsonValue.NumberValue("{id}"))
    return JsonValue.ObjectValue(all)

type Feed:
    events: List[Event]

test "JSON stringify lets JsonEncode override the structural encoding of an alternative":
    if encoded(Event.Created(1)) != "\{\"type\":\"created\",\"id\":1\}": return panic(
        "custom tagged alternative"
    )

    let feed = Feed(events: [Event.Created(1), Event.Deleted(2)])
    let expected = "\{\"events\":[\{\"type\":\"created\",\"id\":1\},\{\"type\":\"deleted\",\"id\":2\}]\}"
    if encoded(feed) != expected: return panic("custom encoding nested in a record")

type Change:
    case Added(id: Int)
    case Removed(id: Int)

test "JSON stringify keeps cases with identical labels distinct by default":
    if encoded(Change.Added(1)) != "\{\"Added\":\{\"id\":1\}\}": return panic(
        "tagged Added"
    )
    if encoded(Change.Removed(1)) != "\{\"Removed\":\{\"id\":1\}\}": return panic(
        "tagged Removed"
    )
