import {expect_equal, expect_false, expect_not_equal, expect_ok, expect_true, fail} from "@std/testing.ms"
import range from "@std/collections.ms"
import {parse, stringify, JsonValue, JsonLimits, JsonError, JsonEncode} from "@std/json.ms"
import {timestamp, duration, clock, Timestamp, Duration, Instant} from "@std/time.ms"
import {Url} from "@std/url.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import {TextError} from "@std/errors.ms"
import BigInt from "@std/bigint.ms"

test "JSON exact numbers Unicode and nested roundtrip":
    let text = "\{\"n\":9007199254740993,\"s\":\"é🙂\",\"a\":[null,true,false]\}"
    let parsed = (parse(text: text) | try expect_ok)
    stringify(value: parsed) | try expect_ok | try expect_equal(expected: text)
    parse(text: "\"\\uD83D\\uDE00\"") | try expect_ok | try expect_equal(
        expected: JsonValue.StringValue("😀")
    )
    try expect_equal(
        (
            stringify(
                value: (parse(text: "null") | try expect_ok),
                max_bytes: 4
            ) | try expect_ok
        ),
        "null"
    )

test "JSON rejects duplicate keys malformed Unicode and trailing values":
    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    for text in [
        "\{\"a\":1,\"\\u0061\":2\}", "\"\\uD800\"", "\"\\uDC00\"", "1 2", "NaN", "[1,]"
    ]:
        parse(text: text) | try expect_equal(expected: invalid)

test "JSON independently enforces byte depth and value budgets":
    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    parse(text: "null", limits: JsonLimits(max_bytes: 3)) | try expect_equal(
        expected: limited
    )
    parse(text: "[[[]]]", limits: JsonLimits(max_depth: 2)) | try expect_equal(
        expected: limited
    )
    parse(text: "[1,2]", limits: JsonLimits(max_values: 2)) | try expect_equal(
        expected: limited
    )
    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidInput)
    parse(text: "null", limits: JsonLimits(max_bytes: -1)) | try expect_equal(
        expected: invalid
    )

test "JSON stringify rejects number text with trailing whitespace":
    let padded: Result[String, JsonError] = error(JsonError.InvalidData)
    stringify(value: JsonValue.NumberValue("1\n")) | try expect_equal(expected: padded)
    stringify(value: JsonValue.NumberValue("1 ")) | try expect_equal(expected: padded)

test "JSON parse bounds nesting even without a depth limit":
    var text = ""
    var closing = ""

    for i in range(0, 150000):
        text = text + "["
        closing = closing + "]"

    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    parse(text: text + closing) | try expect_equal(expected: limited)

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

fn encoded[T](item: T) -> Result[String, Error]:
    return ok((stringify(value: item) | try expect_ok))

test "JSON stringify encodes records in declaration order and omits none fields":
    let request = Request(
        model: "m",
        stream: true,
        user: none,
        temperature: 0.5,
        tags: ["a", "b"]
    )
    let expected = "\{\"model\":\"m\",\"stream\":true,\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    (try encoded(request)) | try expect_equal(expected: expected)
    request.user = some("u")
    let named = "\{\"model\":\"m\",\"stream\":true,\"user\":\"u\",\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    (try encoded(request)) | try expect_equal(expected: named)
    (try encoded(Box[Int](first: 1, second: none))) | try expect_equal(
        expected: "\{\"first\":1\}"
    )
    (try encoded(Box[Int](first: 1, second: some(2)))) | try expect_equal(
        expected: "\{\"first\":1,\"second\":2\}"
    )

test "JSON stringify encodes alternatives and nested optionals":
    let scene = Scene(
        shape: Shape.Circle(2),
        shapes: [Shape.Dot, Shape.Rect(1, 2)],
        note: none
    )
    let expected = "\{\"shape\":\{\"Circle\":\{\"radius\":2\}\},\"shapes\":[\"Dot\",\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
    (try encoded(scene)) | try expect_equal(expected: expected)
    let sparse: List[Optional[Int]] = [some(1), none]
    (try encoded(sparse)) | try expect_equal(expected: "[1,null]")
    let missing: Optional[Int] = none
    (try encoded(missing)) | try expect_equal(expected: "null")

test "JSON stringify keeps map insertion order and encodes scalars exactly":
    let ordered = Map[String, Int]().add("b", 2).add("a", 1)
    (try encoded(ordered)) | try expect_equal(expected: "\{\"b\":2,\"a\":1\}")
    (try encoded(9007199254740993)) | try expect_equal(expected: "9007199254740993")
    (try encoded(1.0)) | try expect_equal(expected: "1")
    (try encoded(0.1)) | try expect_equal(expected: "0.1")
    (try encoded(1e300)) | try expect_equal(expected: "1e+300")
    (try encoded("<é\n")) | try expect_equal(expected: "\"\\u003cé\\n\"")
    let parsed = (parse(text: "\{\"n\":1.50\}") | try expect_ok)
    let mixed = Box[JsonValue](first: parsed, second: none)
    (try encoded(mixed)) | try expect_equal(expected: "\{\"first\":\{\"n\":1.50\}\}")

test "JSON stringify reports cycles non-finite numbers and budgets as errors":
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    var node = Node(label: "a", next: none)
    node.next = some(node)
    stringify(value: node) | try expect_equal(expected: invalid)
    (try encoded(1e308 * 10.0)) | try expect_equal(expected: "null")
    (try encoded(1e308 * 10.0 - 1e308 * 10.0)) | try expect_equal(expected: "null")
    let limited: Result[String, JsonError] = error(JsonError.LimitExceeded)
    stringify(value: "abcdef", max_bytes: 4) | try expect_equal(expected: limited)
    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    stringify(value: 1, max_bytes: -1) | try expect_equal(expected: negative)

test "JSON stringify repeats shared acyclic values and reads current field values":
    let shared = Node(label: "s", next: none)
    let pair = [shared, shared]
    let before = (try encoded(pair))
    shared.label = "changed"
    before | try expect_equal(expected: "[\{\"label\":\"s\"\},\{\"label\":\"s\"\}]")
    (try encoded(pair)) | try expect_not_equal(expected: before)

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
    (try encoded(handler)) | try expect_equal(expected: "\{\"name\":\"h\"\}")
    handler.retries = some(none)
    (try encoded(handler)) | try expect_equal(
        expected: "\{\"name\":\"h\",\"retries\":null\}"
    )
    handler.retries = some(some(3))
    (try encoded(handler)) | try expect_equal(
        expected: "\{\"name\":\"h\",\"retries\":3\}"
    )
    let callbacks = [one, one]
    (try encoded(callbacks)) | try expect_equal(expected: "[null,null]")
    let named = Map[String, Int]().add("a", 1)
    (try encoded(named)) | try expect_equal(expected: "\{\"a\":1\}")
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    stringify(value: one) | try expect_equal(expected: invalid)

test "JSON stringify encodes standard-library values":
    let at = (timestamp(seconds: 1700000000, nanoseconds: 500000000) | try expect_ok)
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
    (try encoded(item)) | try expect_equal(expected: expected)
    (try encoded(TextError.Text("boom"))) | try expect_equal(
        expected: "\{\"Text\":\{\"message\":\"boom\"\}\}"
    )
    let ok: Result[Int, Error] = ok(5)
    (try encoded(ok)) | try expect_equal(expected: "\{\"ok\":\{\"value\":5\}\}")
    (try encoded(JsonError.InvalidData)) | try expect_equal(expected: "\"InvalidData\"")
    (try encoded(Tagged.Named("n", none))) | try expect_equal(
        expected: "\{\"Named\":\{\"name\":\"n\"\}\}"
    )
    (try encoded(Tagged.Plain)) | try expect_equal(expected: "\"Plain\"")

test "JSON stringify encodes scalar map keys and rejects the rest":
    let ints = Map[Int, String]().add(2, "b").add(1, "a")
    (try encoded(ints)) | try expect_equal(expected: "\{\"2\":\"b\",\"1\":\"a\"\}")
    let flags = Map[Bool, Int]().add(true, 1)
    (try encoded(flags)) | try expect_equal(expected: "\{\"true\":1\}")
    let decimals = Map[Decimal, Int]().add(1.50d, 1)
    (try encoded(decimals)) | try expect_equal(expected: "\{\"1.5\":1\}")
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    let records = Map[Money, Int]().add(Money(1), 1)
    stringify(value: records) | try expect_equal(expected: invalid)

test "JSON stringify honors JsonEncode wherever the value appears":
    let invoice = Invoice(total: Money(500), lines: [Money(200), Money(300)])
    let expected = "\{\"total\":\"usd:500\",\"lines\":[\"usd:200\",\"usd:300\"]\}"
    (try encoded(invoice)) | try expect_equal(expected: expected)
    (try encoded(Money(7))) | try expect_equal(expected: "\"usd:7\"")

test "JSON stringify indents like JSON.stringify and clamps at ten":
    let request = Request(
        model: "m",
        stream: true,
        user: none,
        temperature: 0.5,
        tags: ["a"]
    )
    let pretty = (stringify(value: request, indent: 2) | try expect_ok)
    let expected = "\{\n  \"model\": \"m\",\n  \"stream\": true,\n  \"temperature\": 0.5,\n  \"tags\": [\n    \"a\"\n  ]\n\}"
    pretty | try expect_equal(expected: expected)
    let empty: List[Int] = []
    stringify(value: empty, indent: 4) | try expect_ok | try expect_equal(
        expected: "[]"
    )
    stringify(value: [1], indent: 0) | try expect_ok | try expect_equal(expected: "[1]")
    let wide = (stringify(value: [1], indent: 99) | try expect_ok)
    wide | try expect_equal(expected: "[\n          1\n]")
    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    stringify(value: 1, indent: -1) | try expect_equal(expected: negative)

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

test "JSON stringify omits interface values and monotonic instants":
    let who = Named(value: Person(name: "p"))
    let holder = Holder(who: who, at: clock().now(), done: unit)
    (try encoded(holder)) | try expect_equal(expected: "\{\}")
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    stringify(value: clock().now()) | try expect_equal(expected: invalid)
    stringify(value: unit) | try expect_equal(expected: invalid)
    let failed: Result[Int, JsonError] = error(JsonError.LimitExceeded)
    (try encoded(failed)) | try expect_equal(
        expected: "\{\"error\":\{\"cause\":\"LimitExceeded\"\}\}"
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
    (try encoded(Event.Created(1))) | try expect_equal(
        expected: "\{\"type\":\"created\",\"id\":1\}"
    )
    let feed = Feed(events: [Event.Created(1), Event.Deleted(2)])
    let expected = "\{\"events\":[\{\"type\":\"created\",\"id\":1\},\{\"type\":\"deleted\",\"id\":2\}]\}"
    (try encoded(feed)) | try expect_equal(expected: expected)

type Change:
    case Added(id: Int)
    case Removed(id: Int)

test "JSON stringify keeps cases with identical labels distinct by default":
    (try encoded(Change.Added(1))) | try expect_equal(
        expected: "\{\"Added\":\{\"id\":1\}\}"
    )
    (try encoded(Change.Removed(1))) | try expect_equal(
        expected: "\{\"Removed\":\{\"id\":1\}\}"
    )

type Profile:
    name: String
    age: Int = 18
    nickname: Optional[String]
    scores: List[Float]
    labels: Map[String, Int]
    ids: Set[Int]

type Wrapper[T]:
    first: T
    second: Optional[T]
    extra: Int = 7

type Tree:
    label: String
    children: List[Tree]

type Price:
    amount: Decimal
    cents: BigInt

fn decoded[T](text: String) -> Result[T, JsonError]:
    return parse[T](text: text)

test "JSON parse decodes records by field name with defaults and optional fields":
    let text = "\{\"scores\":[1,2.5],\"name\":\"Ada\",\"labels\":\{\"a\":1\},\"ids\":[3,3,4]\}"
    let profile: Profile = (parse[Profile](text: text) | try expect_ok)
    profile.name | try expect_equal(expected: "Ada")
    profile.age | try expect_equal(expected: 18)
    (profile.nickname.is_none()) | try expect_true
    (profile.scores.length() != 2 or profile.scores.at(1).unwrap() != 2.5) | try expect_false
    profile.labels.get("a").unwrap() | try expect_equal(expected: 1)
    profile.ids.length() | try expect_equal(expected: 2)
    let full = "\{\"name\":\"B\",\"age\":30,\"nickname\":\"bee\",\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    let other: Profile = (parse[Profile](text: full) | try expect_ok)
    (other.age != 30 or other.nickname.unwrap() != "bee") | try expect_false

test "JSON parse rejects shape mismatches as InvalidData":
    let invalid: Result[Profile, JsonError] = error(JsonError.InvalidData)
    let missing = "\{\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    parse[Profile](text: missing) | try expect_equal(expected: invalid)
    let unknown = "\{\"name\":\"A\",\"scores\":[],\"labels\":\{\},\"ids\":[],\"extra\":1\}"
    parse[Profile](text: unknown, ignore_unknown_fields: false) | try expect_equal(
        expected: invalid
    )
    let lenient: Profile = (parse[Profile](text: unknown) | try expect_ok)
    lenient.name | try expect_equal(expected: "A")
    let wrong = "\{\"name\":1,\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    parse[Profile](text: wrong) | try expect_equal(expected: invalid)
    let fractional = "\{\"name\":\"A\",\"age\":1.5,\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    parse[Profile](text: fractional) | try expect_equal(expected: invalid)
    let overflow = "\{\"name\":\"A\",\"age\":9223372036854775808,\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    parse[Profile](text: overflow) | try expect_equal(expected: invalid)
    parse[Profile](text: "[]") | try expect_equal(expected: invalid)
    let malformed: Result[Profile, JsonError] = error(JsonError.InvalidData)
    parse[Profile](text: "\{") | try expect_equal(expected: malformed)
    let limited: Result[Profile, JsonError] = error(JsonError.LimitExceeded)
    parse[Profile](text: missing, limits: JsonLimits(max_bytes: 2)) | try expect_equal(
        expected: limited
    )

test "JSON parse decodes alternatives and generic records":
    let shape: Shape = (parse[Shape](text: "\"Dot\"") | try expect_ok)
    shape | try expect_equal(expected: Shape.Dot)
    let circle: Shape = (
        parse[Shape](text: "\{\"Circle\":\{\"radius\":2\}\}") | try expect_ok
    )
    circle | try expect_equal(expected: Shape.Circle(2))
    let invalid: Result[Shape, JsonError] = error(JsonError.InvalidData)
    parse[Shape](text: "\"Circle\"") | try expect_equal(expected: invalid)
    parse[Shape](text: "\{\"Dot\":\{\}\}") | try expect_equal(expected: invalid)
    parse[Shape](text: "\"Square\"") | try expect_equal(expected: invalid)
    parse[Shape](text: "\{\"Circle\":\{\"radius\":1\},\"Dot\":\{\}\}") | try expect_equal(
        expected: invalid
    )
    let scene: Scene = (
        parse[Scene](
            text: "\{\"shape\":\"Dot\",\"shapes\":[\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
        ) | try expect_ok
    )
    scene.shapes.at(0).unwrap() | try expect_equal(expected: Shape.Rect(1, 2))
    let wrapper: Wrapper[Int] = (
        parse[Wrapper[Int]](text: "\{\"first\":1\}") | try expect_ok
    )
    try expect_false(
        (
            wrapper.first != 1
            or not wrapper.second.is_none()
            or wrapper.extra != 7
        )
    )
    let nested: Wrapper[Wrapper[String]] = (
        parse[Wrapper[Wrapper[String]]](
            text: "\{\"first\":\{\"first\":\"x\",\"extra\":1\},\"second\":null\}"
        ) | try expect_ok
    )
    try expect_false(
        (
            nested.first.first != "x"
            or nested.first.extra != 1
            or nested.extra != 7
        )
    )

test "JSON parse decodes recursive types exact numbers and passthrough values":
    let tree: Tree = (
        parse[Tree](
            text: "\{\"label\":\"r\",\"children\":[\{\"label\":\"c\",\"children\":[]\}]\}"
        ) | try expect_ok
    )
    tree.children.at(0).unwrap().label | try expect_equal(expected: "c")
    let price: Price = (
        parse[Price](
            text: "\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
        ) | try expect_ok
    )
    let price_text: Result[String, JsonError] = ok(
        "\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
    )
    stringify(value: price) | try expect_equal(expected: price_text)
    let raw = (parse(text: "\{\"n\":1.50\}") | try expect_ok)
    let boxed: Wrapper[JsonValue] = (
        parse[Wrapper[JsonValue]](
            text: "\{\"first\":\{\"n\":1.50\}\}"
        ) | try expect_ok
    )
    boxed.first | try expect_equal(expected: raw)
    let list: List[Optional[Int]] = (
        parse[List[Optional[Int]]](text: "[1,null]") | try expect_ok
    )
    list.at(1).unwrap().is_some() | try expect_false

test "JSON parse inverts stringify and works in generic code":
    let profile = Profile(
        name: "Ada",
        age: 20,
        nickname: some("a"),
        scores: [0.5],
        labels: Map[String, Int]().add("k", 1),
        ids: Set[Int]().add(2)
    )
    let text = (stringify(value: profile) | try expect_ok)
    let again: Profile = (decoded[Profile](text) | try expect_ok)
    stringify(value: again) | try expect_ok | try expect_equal(expected: text)
    again.nickname.unwrap() | try expect_equal(expected: "a")
    let shapes: List[Shape] = [Shape.Dot, Shape.Rect(3, 4)]
    let shapesBack: List[Shape] = (
        decoded[List[Shape]](
            (stringify(value: shapes) | try expect_ok)
        ) | try expect_ok
    )
    shapesBack.at(1).unwrap() | try expect_equal(expected: Shape.Rect(3, 4))

fn load_profile(text: String) -> Result[Profile, JsonError]:
    let profile = try parse[Profile](text: text)
    return ok(profile)

fn load_default(text: String) -> Result[JsonValue, JsonError]:
    return parse(text: text)

test "JSON parse takes its type from an explicit argument, the expected result or the JsonValue default":
    let profile = (
        load_profile(
            "\{\"name\":\"Ada\",\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
        ) | try expect_ok
    )
    profile.name | try expect_equal(expected: "Ada")
    let invalid: Result[Profile, JsonError] = error(JsonError.InvalidData)
    load_profile("\{\"name\":1\}") | try expect_equal(expected: invalid)
    let raw = (load_default("\{\"a\":[1]\}") | try expect_ok)
    let again = (parse(text: "\{\"a\":[1]\}") | try expect_ok)
    raw | try expect_equal(expected: again)

test "JSON parse reads what stringify writes for standard values and scalar map keys":
    let at = (timestamp(seconds: 1700000000, nanoseconds: 500000000) | try expect_ok)
    let link = Url(
        scheme: "https",
        host: "example.com",
        port: some(8080),
        path: "/a",
        query: "x=1",
        fragment: ""
    )
    let item = Stamped(at: at, took: duration(1500), data: "hi".to_bytes(), link: link)
    let text = (stringify(value: item) | try expect_ok)
    let back: Stamped = (parse[Stamped](text: text) | try expect_ok)
    stringify(value: back) | try expect_ok | try expect_equal(expected: text)
    back.took | try expect_equal(expected: duration(1500))
    let ints: Map[Int, String] = (
        parse[Map[Int, String]](
            text: "\{\"2\":\"b\",\"1\":\"a\"\}"
        ) | try expect_ok
    )
    ints.get(2).unwrap() | try expect_equal(expected: "b")
    let bad: Result[Map[Int, String], JsonError] = error(JsonError.InvalidData)
    parse[Map[Int, String]](text: "\{\"x\":\"b\"\}") | try expect_equal(expected: bad)
    let flags: Map[Bool, Int] = (
        parse[Map[Bool, Int]](text: "\{\"true\":1\}") | try expect_ok
    )
    flags.get(true).unwrap() | try expect_equal(expected: 1)
    let kinds: Map[Tagged, Int] = (
        parse[Map[Tagged, Int]](text: "\{\"Plain\":3\}") | try expect_ok
    )
    kinds.get(Tagged.Plain).unwrap() | try expect_equal(expected: 3)

test "JSON parse needs a default for fields without a JSON form":
    let outcome = parse[Handler](text: "\{\"name\":\"n\"\}")
    outcome.is_ok() | try expect_false

test "JSON parse reads standard alternatives and rejects keys that collide":
    let good: Result[Int, JsonError] = (
        parse[Result[Int, JsonError]](
            text: "\{\"ok\":\{\"value\":5\}\}"
        ) | try expect_ok
    )
    let want_ok: Result[Int, JsonError] = ok(5)
    good | try expect_equal(expected: want_ok)
    let failed: Result[Int, JsonError] = (
        parse[Result[Int, JsonError]](
            text: "\{\"error\":\{\"cause\":\"InvalidData\"\}\}"
        ) | try expect_ok
    )
    let want_error: Result[Int, JsonError] = error(JsonError.InvalidData)
    failed | try expect_equal(expected: want_error)
    let kind: JsonError = (parse[JsonError](text: "\"LimitExceeded\"") | try expect_ok)
    kind | try expect_equal(expected: JsonError.LimitExceeded)
    let collide: Result[Map[Int, String], JsonError] = error(JsonError.InvalidData)
    parse[Map[Int, String]](text: "\{\"1\":\"a\",\"01\":\"b\"\}") | try expect_equal(
        expected: collide
    )

type Link:
    next: Optional[Link]
    n: Int

type Defaults:
    a: Int = 1
    b: Int = a + 1
    c: String = "x{b}"

type Kw:
    type_: Int
    func: Int
    range: Int

type Pair[A, B]:
    left: A
    right: B

type Op:
    case Add(left: Int, right: Int)
    case Neg(v: Optional[Int])
    case Nop

type Wrap:
    ops: List[Op]
    pairs: List[Pair[Int, Op]]
    byTime: Map[Duration, String]

test "JSON stringify fails on nesting deeper than parse accepts":
    var head = Link(next: none, n: 0)
    for i in range(1, 300000):
        head = Link(next: some(head), n: i)
    let r = stringify(head)
    r.is_ok() | try expect_false

test "JSON parse runs field defaults that read earlier fields":
    let d = (parse[Defaults](text: "\{\"a\":5\}") | try expect_ok)
    if d.b != 6 or d.c != "x6": return fail("default chain {d.b} {d.c}")

test "JSON round trips fields named like Go keywords":
    let k = Kw(type_: 1, func: 2, range: 3)
    let t = (stringify(k) | try expect_ok)
    let back = (parse[Kw](text: t) | try expect_ok)
    back.range | try expect_equal(expected: 3)

test "JSON round trips generic records alternatives and Duration keys":
    let w = Wrap(
        ops: [Op.Add(1, 2), Op.Neg(none), Op.Neg(some(3)), Op.Nop],
        pairs: [Pair(left: 1, right: Op.Nop)],
        byTime: Map[Duration, String]().add(duration(5), "five")
    )
    let t = (stringify(w) | try expect_ok)
    let back = (parse[Wrap](text: t) | try expect_ok)
    stringify(back) | try expect_ok | try expect_equal(expected: t)

test "JSON parse returns InvalidData for targets that cannot be read":
    parse[Unit](text: "null").is_ok() | try expect_false
    let f = parse[fn() -> Int](text: "1")
    f.is_ok() | try expect_false
    parse[Int](text: "-0").is_error() | try expect_false
    parse[Float](text: "1e999").is_ok() | try expect_false
    parse[String](text: "1").is_ok() | try expect_false
    parse[List[Int]](text: "[1,\"a\"]").is_ok() | try expect_false
