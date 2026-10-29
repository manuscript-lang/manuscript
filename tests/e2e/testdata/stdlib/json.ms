import {expect_equal, expect_false, expect_not_equal, fail} from "@std/test.ms"
import {parse, stringify, JsonValue, JsonLimits, JsonError, JsonEncode} from "@std/json.ms"
import {timestamp, nanoseconds, clock, Timestamp, Duration, Instant} from "@std/time.ms"
import Url from "@std/net.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import {Data, TextError} from "@std/core.ms"
import BigInt from "@std/math.ms"

test "JSON exact numbers Unicode and nested roundtrip":
    let text = "\{\"n\":9007199254740993,\"s\":\"é🙂\",\"a\":[null,true,false]\}"
    try expect_equal((try parse(text) | try stringify), text)
    try expect_equal((try parse("\"\\uD83D\\uDE00\"")), JsonValue.StringValue("😀"))
    try expect_equal((try parse("null") | try stringify(4)), "null")

test "JSON rejects duplicate keys malformed Unicode and trailing values":
    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    for text in [
        "\{\"a\":1,\"\\u0061\":2\}", "\"\\uD800\"", "\"\\uDC00\"", "1 2", "NaN", "[1,]"
    ]:
        try expect_equal(parse(text), invalid)

test "JSON independently enforces byte depth and value budgets":
    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    try expect_equal(parse("null", JsonLimits(3)), limited)
    try expect_equal(parse("[[[]]]", JsonLimits(max_depth: 2)), limited)
    try expect_equal(parse("[1,2]", JsonLimits(max_values: 2)), limited)

    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidInput)
    try expect_equal(parse("null", JsonLimits(-1)), invalid)

test "JSON untyped parse keeps document shape and releases partial trees on failure":
    let long = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    let text = (
        "[\{\""
        + long
        + "\":[1,\""
        + long
        + "\",\{\}],\"k\\n\":null\},[],true,-1.5e3,\"\\u00e9\"]"
    )
    let parsed = try parse(text)
    try expect_equal(try stringify(parsed), text.replace("\\u00e9", "é"))

    var wide = "\{"
    for i in 0..40:
        wide += (
            "\"k"
            + i.to_string()
            + "\":[\""
            + long
            + i.to_string()
            + "\",\{\"n\":"
            + i.to_string()
            + "\}],"
        )

    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    try expect_equal(parse(wide + "\"k7\":0\}"), invalid)
    try expect_equal(parse(wide + "\"k40\":["), invalid)

    let fine = try parse(wide + "\"k40\":0\}")
    try expect_equal(try stringify(fine), wide + "\"k40\":0\}")

test "JSON stringify rejects number text with trailing whitespace":
    let padded: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(JsonValue.NumberValue("1\n")), padded)
    try expect_equal(stringify(JsonValue.NumberValue("1 ")), padded)

test "JSON parse bounds nesting even without a depth limit":
    var text = ""
    var closing = ""

    for i in 0..150000:
        text += "["
        closing += "]"

    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    try expect_equal(parse(text + closing), limited)

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

fn encoded[T: Data](item: T) Result[String, Error]:
    return stringify(item)

test "JSON stringify encodes records in declaration order and omits none fields":
    var request = Request("m", stream: true, none, 0.5, ["a", "b"])
    let expected = "\{\"model\":\"m\",\"stream\":true,\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    try expect_equal((try encoded(request)), expected)
    request.user = some("u")

    let named = "\{\"model\":\"m\",\"stream\":true,\"user\":\"u\",\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    try expect_equal((try encoded(request)), named)
    try expect_equal((try encoded(Box[Int](1, none))), "\{\"first\":1\}")
    try expect_equal(
        (try encoded(Box[Int](1, some(2)))), "\{\"first\":1,\"second\":2\}"
    )

test "JSON stringify encodes alternatives and nested optionals":
    let scene = Scene(Shape.Circle(2), [Shape.Dot, Shape.Rect(1, 2)], none)
    let expected = "\{\"shape\":\{\"Circle\":\{\"radius\":2\}\},\"shapes\":[\"Dot\",\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
    try expect_equal((try encoded(scene)), expected)

    let sparse: List[Optional[Int]] = [some(1), none]
    try expect_equal((try encoded(sparse)), "[1,null]")

    let missing: Optional[Int] = none
    try expect_equal((try encoded(missing)), "null")

test "JSON stringify encodes scalars exactly":
    try expect_equal((try encoded(9007199254740993)), "9007199254740993")
    try expect_equal((try encoded(1.0)), "1")
    try expect_equal((try encoded(0.1)), "0.1")
    try expect_equal((try encoded(1e300)), "1e+300")
    try expect_equal((try encoded("<é\n")), "\"<é\\n\"")

    let parsed = try parse("\{\"n\":1.50\}")
    let mixed = Box[JsonValue](parsed, none)
    try expect_equal((try encoded(mixed)), "\{\"first\":\{\"n\":1.50\}\}")

test "JSON stringify reports non-finite numbers and budgets as errors":
    try expect_equal((try encoded(1e308 * 10.0)), "null")
    try expect_equal((try encoded(1e308 * 10.0 - 1e308 * 10.0)), "null")

    let limited: Result[String, JsonError] = error(JsonError.LimitExceeded)
    try expect_equal(stringify("abcdef", 4), limited)

    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    try expect_equal(stringify(1, -1), negative)

test "JSON stringify repeats shared acyclic values and reads current field values":
    let shared = Node("s", none)
    var pair = [shared.clone(), shared.clone()]
    let before = try encoded(pair)
    pair.set(0, Node("changed", none))
    try expect_equal(before, "[\{\"label\":\"s\"\},\{\"label\":\"s\"\}]")
    try expect_not_equal((try encoded(pair)), before)

type Handler:
    name: String
    retries: Optional[Optional[Int]]
    note: Optional[String]

type Money:
    cents: Int

impl JsonEncode for Money:
    fn to_json() JsonValue:
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

test "JSON stringify omits none fields and keeps nested optionals":
    var handler = Handler("h", none, none)
    try expect_equal((try encoded(handler)), "\{\"name\":\"h\"\}")
    handler.retries = some(none)
    try expect_equal((try encoded(handler)), "\{\"name\":\"h\",\"retries\":null\}")
    handler.retries = some(some(3))
    try expect_equal((try encoded(handler)), "\{\"name\":\"h\",\"retries\":3\}")

test "JSON stringify encodes standard-library values":
    let at = try timestamp(1700000000, 500000000)
    let link = Url("https", "example.com", some(8080), "/a", "x=1", "")
    let item = Stamped(at, nanoseconds(1500), "hi".to_bytes(), link)
    let expected = "\{\"at\":\"2023-11-14T22:13:20.5Z\",\"took\":1500,\"data\":\"aGk=\",\"link\":\"https://example.com:8080/a?x=1\"\}"
    try expect_equal((try encoded(item)), expected)
    try expect_equal((try encoded(TextError("boom"))), "\{\"text\":\"boom\"\}")

    let ok: Result[Int, JsonError] = ok(5)
    try expect_equal((try encoded(ok)), "\{\"ok\":\{\"value\":5\}\}")
    try expect_equal((try encoded(JsonError.InvalidData)), "\"InvalidData\"")
    try expect_equal(
        (try encoded(Tagged.Named("n", none))), "\{\"Named\":\{\"name\":\"n\"\}\}"
    )
    try expect_equal((try encoded(Tagged.Plain)), "\"Plain\"")

test "JSON stringify honors JsonEncode wherever the value appears":
    let invoice = Invoice(Money(500), [Money(200), Money(300)])
    let expected = "\{\"total\":\"usd:500\",\"lines\":[\"usd:200\",\"usd:300\"]\}"
    try expect_equal((try encoded(invoice)), expected)
    try expect_equal((try encoded(Money(7))), "\"usd:7\"")

test "JSON stringify indents like JSON.stringify and clamps at ten":
    let request = Request("m", stream: true, none, 0.5, ["a"])
    let pretty = try stringify(request, indent: 2)
    let expected = "\{\n  \"model\": \"m\",\n  \"stream\": true,\n  \"temperature\": 0.5,\n  \"tags\": [\n    \"a\"\n  ]\n\}"
    try expect_equal(pretty, expected)

    let empty: List[Int] = []
    try expect_equal((try stringify(empty, indent: 4)), "[]")
    try expect_equal((try stringify([1], indent: 0)), "[1]")

    let wide = try stringify([1], indent: 99)
    try expect_equal(wide, "[\n          1\n]")

    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    try expect_equal(stringify(1, indent: -1), negative)

type Holder:
    done: Unit

test "JSON stringify omits a Unit field and rejects a Unit root":
    let holder = Holder(unit)
    try expect_equal((try encoded(holder)), "\{\}")

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(unit), invalid)

    let failed: Result[Int, JsonError] = error(JsonError.LimitExceeded)
    try expect_equal(
        (try encoded(failed)), "\{\"error\":\{\"cause\":\"LimitExceeded\"\}\}"
    )

type Event:
    case Created(id: Int)
    case Deleted(id: Int)

impl JsonEncode for Event:
    fn to_json() JsonValue:
        match self:
            Created(id): return tagged("created", id)
            Deleted(id): return tagged("deleted", id)

fn tagged(kind: String, id: Int) JsonValue:
    var fields = Map[String, JsonValue]()
    fields.add("type", JsonValue.StringValue(kind))
    fields.add("id", JsonValue.NumberValue("{id}"))

    let all = fields
    return JsonValue.ObjectValue(all)

type Feed:
    events: List[Event]

test "JSON stringify lets JsonEncode override the structural encoding of an alternative":
    try expect_equal(
        (try encoded(Event.Created(1))), "\{\"type\":\"created\",\"id\":1\}"
    )

    let feed = Feed([Event.Created(1), Event.Deleted(2)])
    let expected = "\{\"events\":[\{\"type\":\"created\",\"id\":1\},\{\"type\":\"deleted\",\"id\":2\}]\}"
    try expect_equal((try encoded(feed)), expected)

type Change:
    case Added(id: Int)
    case Removed(id: Int)

test "JSON stringify keeps cases with identical labels distinct by default":
    try expect_equal((try encoded(Change.Added(1))), "\{\"Added\":\{\"id\":1\}\}")
    try expect_equal((try encoded(Change.Removed(1))), "\{\"Removed\":\{\"id\":1\}\}")

type Profile:
    name: String
    age: Int = 18
    nickname: Optional[String]
    scores: List[Float]

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

fn decoded[T: Data](text: String) Result[T, JsonError]:
    return parse[T](text)

test "JSON parse decodes records by field name with defaults and optional fields":
    let text = "\{\"scores\":[1,2.5],\"name\":\"Ada\",\"extra\":1\}"
    let profile: Profile = try parse[Profile](text)
    try expect_equal(profile.name, "Ada")
    try expect_equal(profile.age, 18)
    try expect_false(not profile.nickname.is_none())
    try expect_false(profile.scores.length() != 2 or profile.scores.get(1) != 2.5)

    let full = "\{\"name\":\"B\",\"age\":30,\"nickname\":\"bee\",\"scores\":[]\}"
    let other: Profile = try parse[Profile](full)
    try expect_false(other.age != 30 or other.nickname.get() != "bee")

test "JSON parse rejects shape mismatches as InvalidData":
    let invalid: Result[Profile, JsonError] = error(JsonError.InvalidData)
    let missing = "\{\"scores\":[]\}"
    try expect_equal(parse[Profile](missing), invalid)

    let unknown = "\{\"name\":\"A\",\"scores\":[],\"extra\":1\}"
    try expect_equal(parse[Profile](unknown, ignore_unknown_fields: false), invalid)

    let lenient: Profile = try parse[Profile](unknown)
    try expect_equal(lenient.name, "A")

    let wrong = "\{\"name\":1,\"scores\":[]\}"
    try expect_equal(parse[Profile](wrong), invalid)

    let fractional = "\{\"name\":\"A\",\"age\":1.5,\"scores\":[]\}"
    try expect_equal(parse[Profile](fractional), invalid)

    let overflow = "\{\"name\":\"A\",\"age\":9223372036854775808,\"scores\":[]\}"
    try expect_equal(parse[Profile](overflow), invalid)
    try expect_equal(parse[Profile]("[]"), invalid)

    let malformed: Result[Profile, JsonError] = error(JsonError.InvalidData)
    try expect_equal(parse[Profile]("\{"), malformed)

    let limited: Result[Profile, JsonError] = error(JsonError.LimitExceeded)
    try expect_equal(parse[Profile](missing, JsonLimits(2)), limited)

test "JSON parse decodes alternatives and generic records":
    let shape: Shape = try parse[Shape]("\"Dot\"")
    try expect_equal(shape, Shape.Dot)

    let circle: Shape = try parse[Shape]("\{\"Circle\":\{\"radius\":2\}\}")
    try expect_equal(circle, Shape.Circle(2))

    let invalid: Result[Shape, JsonError] = error(JsonError.InvalidData)
    try expect_equal(parse[Shape]("\"Circle\""), invalid)
    try expect_equal(parse[Shape]("\{\"Dot\":\{\}\}"), invalid)
    try expect_equal(parse[Shape]("\"Square\""), invalid)
    try expect_equal(
        parse[Shape]("\{\"Circle\":\{\"radius\":1\},\"Dot\":\{\}\}"), invalid
    )

    let scene: Scene = try parse[Scene](
        "\{\"shape\":\"Dot\",\"shapes\":[\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
    )
    try expect_equal(scene.shapes.get(0), Shape.Rect(1, 2))

    let wrapper: Wrapper[Int] = try parse[Wrapper[Int]]("\{\"first\":1\}")
    try expect_false(
        (
            wrapper.first != 1
            or not wrapper.second.is_none()
            or wrapper.extra != 7
        )
    )

    let nested: Wrapper[Wrapper[String]] = try parse[Wrapper[Wrapper[String]]](
        "\{\"first\":\{\"first\":\"x\",\"extra\":1\},\"second\":null\}"
    )
    try expect_false(
        (
            nested.first.first != "x"
            or nested.first.extra != 1
            or nested.extra != 7
        )
    )

test "JSON parse decodes recursive types exact numbers and passthrough values":
    let tree: Tree = try parse[Tree](
        "\{\"label\":\"r\",\"children\":[\{\"label\":\"c\",\"children\":[]\}]\}"
    )
    try expect_equal(tree.children.get(0).label, "c")

    let price: Price = try parse[Price](
        "\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
    )
    let price_text: Result[String, JsonError] = ok(
        "\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
    )
    try expect_equal(stringify(price), price_text)

    let raw = try parse("\{\"n\":1.50\}")
    let boxed: Wrapper[JsonValue] = try parse[Wrapper[JsonValue]](
        "\{\"first\":\{\"n\":1.50\}\}"
    )
    try expect_equal(boxed.first, raw)

    let list: List[Optional[Int]] = try parse[List[Optional[Int]]]("[1,null]")
    try expect_false(list.get(1).is_some())

test "JSON parse inverts stringify and works in generic code":
    let profile = Profile("Ada", 20, some("a"), [0.5])
    let text = try stringify(profile)
    let again: Profile = try decoded[Profile](text)
    try expect_equal((try stringify(again)), text)
    try expect_equal(again.nickname.get(), "a")

    let shapes: List[Shape] = [Shape.Dot, Shape.Rect(3, 4)]
    let shapesBack: List[Shape] = try decoded[List[Shape]](try stringify(shapes))
    try expect_equal(shapesBack.get(1), Shape.Rect(3, 4))

fn load_profile(text: String) Result[Profile, JsonError]:
    let profile = try parse[Profile](text)
    return ok(profile)

fn load_default(text: String) Result[JsonValue, JsonError]:
    return parse(text)

test "JSON parse takes its type from an explicit argument, the expected result or the JsonValue default":
    let profile = try load_profile("\{\"name\":\"Ada\",\"scores\":[]\}")
    try expect_equal(profile.name, "Ada")

    let invalid: Result[Profile, JsonError] = error(JsonError.InvalidData)
    try expect_equal(load_profile("\{\"name\":1\}"), invalid)

    let raw = try load_default("\{\"a\":[1]\}")
    let again = try parse("\{\"a\":[1]\}")
    try expect_equal(raw, again)

test "JSON parse reads what stringify writes for standard values and scalar map keys":
    let at = try timestamp(1700000000, 500000000)
    let link = Url("https", "example.com", some(8080), "/a", "x=1", "")
    let item = Stamped(at, nanoseconds(1500), "hi".to_bytes(), link)
    let text = try stringify(item)
    let back: Stamped = try parse[Stamped](text)
    try expect_equal((try stringify(back)), text)
    try expect_equal(back.took, nanoseconds(1500))

test "JSON parse reads standard alternatives and rejects keys that collide":
    let good: Result[Int, JsonError] = try parse[Result[Int, JsonError]](
        "\{\"ok\":\{\"value\":5\}\}"
    )
    let want_ok: Result[Int, JsonError] = ok(5)
    try expect_equal(good, want_ok)

    let failed: Result[Int, JsonError] = try parse[Result[Int, JsonError]](
        "\{\"error\":\{\"cause\":\"InvalidData\"\}\}"
    )
    let want_error: Result[Int, JsonError] = error(JsonError.InvalidData)
    try expect_equal(failed, want_error)

    let kind: JsonError = try parse[JsonError]("\"LimitExceeded\"")
    try expect_equal(kind, JsonError.LimitExceeded)

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

test "JSON stringify fails on nesting deeper than parse accepts":
    var head = Link(none, 0)
    for i in 1..300000:
        head = Link(some(head), i)

    let r = stringify(head)
    try expect_false(r.is_ok())

test "JSON parse runs field defaults that read earlier fields":
    let d = try parse[Defaults]("\{\"a\":5\}")
    if d.b != 6 or d.c != "x6": return fail("default chain {d.b} {d.c}")

test "JSON round trips fields named like Go keywords":
    let k = Kw(1, 2, 3)
    let t = try stringify(k)
    let back = try parse[Kw](t)
    try expect_equal(back.range, 3)

test "JSON round trips generic records and alternatives":
    let w = Wrap(
        [Op.Add(1, 2), Op.Neg(none), Op.Neg(some(3)), Op.Nop], [Pair(1, Op.Nop)]
    )
    let t = try stringify(w)
    let back = try parse[Wrap](t)
    try expect_equal((try stringify(back)), t)

test "JSON parse returns InvalidData for targets that cannot be read":
    try expect_false(parse[Unit]("null").is_ok())
    try expect_false(parse[Int]("-0").is_error())
    try expect_false(parse[Float]("1e999").is_ok())
    try expect_false(parse[String]("1").is_ok())
    try expect_false(parse[List[Int]]("[1,\"a\"]").is_ok())

type BoundReading:
    id: Int

test "JSON parse and stringify bound to a type argument pipe like the call":
    let read = parse[List[BoundReading]]
    let write = stringify[BoundReading]
    let items = "[\{\"id\":1\},\{\"id\":2\}]" | read
    try expect_equal(items, ok([BoundReading(1), BoundReading(2)]))
    try expect_equal(BoundReading(1) | write, ok("\{\"id\":1\}"))

test "JSON Decimal fields out of range or inexact are InvalidData":
    let invalid: Result[Price, JsonError] = error(JsonError.InvalidData)
    let tiny = "\{\"amount\":1e-9990,\"cents\":1\}"
    try expect_equal(parse[Price](tiny), invalid)

    let huge = "\{\"amount\":1e9990,\"cents\":1\}"
    try expect_equal(parse[Price](huge), invalid)

    let wide = "\{\"amount\":0.1234567890123456789012345678901234567890,\"cents\":1\}"
    try expect_equal(parse[Price](wide), invalid)
