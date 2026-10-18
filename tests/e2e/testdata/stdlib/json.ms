import range from "@std/collections.ms"
import {parse, stringify, JsonValue, JsonLimits, JsonError, JsonEncode} from "@std/json.ms"
import {timestamp, duration, clock, Timestamp, Duration, Instant} from "@std/time.ms"
import {Url} from "@std/url.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import {TextError} from "@std/errors.ms"
import BigInt from "@std/bigint.ms"
import panic from "@std/faults.ms"

test "JSON exact numbers Unicode and nested roundtrip":
    let text = "\{\"n\":9007199254740993,\"s\":\"é🙂\",\"a\":[null,true,false]\}"
    if (try parse(text) | try stringify) != text: return panic(
        "JSON precision or order"
    )
    if (try parse("\"\\uD83D\\uDE00\"")) != JsonValue.StringValue("😀"): return panic(
        "surrogate pair"
    )
    if ((try parse("null") | try stringify(4)) != "null"): return panic("exact budget")

test "JSON rejects duplicate keys malformed Unicode and trailing values":
    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    for text in [
        "\{\"a\":1,\"\\u0061\":2\}", "\"\\uD800\"", "\"\\uDC00\"", "1 2", "NaN", "[1,]"
    ]:
        if parse(text) != invalid: return panic("malformed JSON accepted")

test "JSON independently enforces byte depth and value budgets":
    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    if (parse("null", JsonLimits(3)) != limited): return panic("JSON byte budget")
    if (parse("[[[]]]", JsonLimits(max_depth: 2)) != limited): return panic(
        "JSON depth budget"
    )
    if (parse("[1,2]", JsonLimits(max_values: 2)) != limited): return panic(
        "JSON value budget"
    )

    let invalid: Result[JsonValue, JsonError] = error(JsonError.InvalidInput)
    if (parse("null", JsonLimits(-1)) != invalid): return panic("negative JSON budget")

test "JSON stringify rejects number text with trailing whitespace":
    let padded: Result[String, JsonError] = error(JsonError.InvalidData)
    if stringify(JsonValue.NumberValue("1\n")) != padded: return panic(
        "trailing newline"
    )
    if stringify(JsonValue.NumberValue("1 ")) != padded: return panic("trailing space")

test "JSON parse bounds nesting even without a depth limit":
    var text = ""
    var closing = ""

    for i in range(0, 150000):
        text += "["
        closing += "]"

    let limited: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    if parse(text + closing) != limited: return panic("unbounded nesting")

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

fn encoded[T](item: T) Result[String, Error]:
    return stringify(item)

test "JSON stringify encodes records in declaration order and omits none fields":
    let request = Request("m", stream: true, none, 0.5, ["a", "b"])
    let expected = "\{\"model\":\"m\",\"stream\":true,\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    if (try encoded(request)) != expected: return panic(
        "record order or omitted none field"
    )

    request.user = some("u")
    let named = "\{\"model\":\"m\",\"stream\":true,\"user\":\"u\",\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
    if (try encoded(request)) != named: return panic("present optional field")
    if (try encoded(Box[Int](1, none))) != "\{\"first\":1\}": return panic(
        "generic record order"
    )
    if ((try encoded(Box[Int](1, some(2)))) != "\{\"first\":1,\"second\":2\}"): return panic(
        "generic optional field"
    )

test "JSON stringify encodes alternatives and nested optionals":
    let scene = Scene(Shape.Circle(2), [Shape.Dot, Shape.Rect(1, 2)], none)
    let expected = "\{\"shape\":\{\"Circle\":\{\"radius\":2\}\},\"shapes\":[\"Dot\",\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
    if (try encoded(scene)) != expected: return panic("alternative encoding")

    let sparse: List[Optional[Int]] = [some(1), none]
    if (try encoded(sparse)) != "[1,null]": return panic("none inside a list is null")

    let missing: Optional[Int] = none
    if (try encoded(missing)) != "null": return panic("root none is null")

test "JSON stringify keeps map insertion order and encodes scalars exactly":
    let ordered = Map[String, Int]().add("b", 2).add("a", 1)
    if (try encoded(ordered)) != "\{\"b\":2,\"a\":1\}": return panic(
        "map insertion order"
    )
    if (try encoded(9007199254740993)) != "9007199254740993": return panic("large Int")
    if (try encoded(1.0)) != "1": return panic("whole Float")
    if (try encoded(0.1)) != "0.1": return panic("shortest Float")
    if (try encoded(1e300)) != "1e+300": return panic("exponent Float")
    if (try encoded("<é\n")) != "\"\\u003cé\\n\"": return panic("string escaping")

    let parsed = try parse("\{\"n\":1.50\}")
    let mixed = Box[JsonValue](parsed, none)
    if (try encoded(mixed)) != "\{\"first\":\{\"n\":1.50\}\}": return panic(
        "JsonValue passthrough"
    )

test "JSON stringify reports cycles non-finite numbers and budgets as errors":
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    let node = Node("a", none)
    node.next = some(node)
    if stringify(node) != invalid: return panic("cyclic record")
    if (try encoded(1e308 * 10.0)) != "null": return panic("infinite Float is null")
    if (try encoded(1e308 * 10.0 - 1e308 * 10.0)) != "null": return panic(
        "NaN Float is null"
    )

    let limited: Result[String, JsonError] = error(JsonError.LimitExceeded)
    if stringify("abcdef", 4) != limited: return panic("output budget")

    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    if stringify(1, -1) != negative: return panic("negative budget")

test "JSON stringify repeats shared acyclic values and reads current field values":
    let shared = Node("s", none)
    let pair = [shared, shared]
    let before = try encoded(pair)
    shared.label = "changed"
    if before != "[\{\"label\":\"s\"\},\{\"label\":\"s\"\}]": return panic(
        "shared value written twice"
    )
    if (try encoded(pair)) == before: return panic(
        "stringify reads current field values"
    )

fn one() Int:
    return 1

type Handler:
    name: String
    callback: fn() Int
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

test "JSON stringify omits values without a JSON form and writes null for list elements":
    let handler = Handler("h", one, none, none)
    if (try encoded(handler)) != "\{\"name\":\"h\"\}": return panic(
        "function and none fields omitted"
    )

    handler.retries = some(none)
    if (try encoded(handler)) != "\{\"name\":\"h\",\"retries\":null\}": return panic(
        "some(none) is null"
    )

    handler.retries = some(some(3))
    if (try encoded(handler)) != "\{\"name\":\"h\",\"retries\":3\}": return panic(
        "nested some"
    )

    let callbacks = [one, one]
    if (try encoded(callbacks)) != "[null,null]": return panic(
        "functions in a list are null"
    )

    let named = Map[String, Int]().add("a", 1)
    if (try encoded(named)) != "\{\"a\":1\}": return panic("map")

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    if stringify(one) != invalid: return panic("root function has no JSON form")

test "JSON stringify encodes standard-library values":
    let at = try timestamp(1700000000, 500000000)
    let link = Url("https", "example.com", some(8080), "/a", "x=1", "")
    let item = Stamped(at, duration(1500), "hi".to_bytes(), link)
    let expected = "\{\"at\":\"2023-11-14T22:13:20.5Z\",\"took\":1500,\"data\":\"aGk=\",\"link\":\"https://example.com:8080/a?x=1\"\}"
    if (try encoded(item)) != expected: return panic("timestamp duration bytes url")
    if (try encoded(TextError.Text("boom"))) != "\{\"Text\":\{\"message\":\"boom\"\}\}": return panic(
        "concrete error is structural"
    )

    let ok: Result[Int, Error] = ok(5)
    if (try encoded(ok)) != "\{\"ok\":\{\"value\":5\}\}": return panic(
        "result ok payload"
    )
    if (try encoded(JsonError.InvalidData)) != "\"InvalidData\"": return panic(
        "standard case name"
    )
    if (try encoded(Tagged.Named("n", none))) != "\{\"Named\":\{\"name\":\"n\"\}\}": return panic(
        "payload case omits none"
    )
    if (try encoded(Tagged.Plain)) != "\"Plain\"": return panic("payloadless case")

test "JSON stringify encodes scalar map keys and rejects the rest":
    let ints = Map[Int, String]().add(2, "b").add(1, "a")
    if (try encoded(ints)) != "\{\"2\":\"b\",\"1\":\"a\"\}": return panic("Int keys")

    let flags = Map[Bool, Int]().add(true, 1)
    if (try encoded(flags)) != "\{\"true\":1\}": return panic("Bool keys")

    let decimals = Map[Decimal, Int]().add(1.50d, 1)
    if (try encoded(decimals)) != "\{\"1.5\":1\}": return panic("Decimal keys")

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    let records = Map[Money, Int]().add(Money(1), 1)
    if stringify(records) != invalid: return panic("record keys")

test "JSON stringify honors JsonEncode wherever the value appears":
    let invoice = Invoice(Money(500), [Money(200), Money(300)])
    let expected = "\{\"total\":\"usd:500\",\"lines\":[\"usd:200\",\"usd:300\"]\}"
    if (try encoded(invoice)) != expected: return panic("to_json hook")
    if (try encoded(Money(7))) != "\"usd:7\"": return panic("root hook")

test "JSON stringify indents like JSON.stringify and clamps at ten":
    let request = Request("m", stream: true, none, 0.5, ["a"])
    let pretty = try stringify(request, indent: 2)
    let expected = "\{\n  \"model\": \"m\",\n  \"stream\": true,\n  \"temperature\": 0.5,\n  \"tags\": [\n    \"a\"\n  ]\n\}"
    if pretty != expected: return panic("indented output")

    let empty: List[Int] = []
    if (try stringify(empty, indent: 4)) != "[]": return panic("empty container")
    if (try stringify([1], indent: 0)) != "[1]": return panic("zero indent is compact")

    let wide = try stringify([1], indent: 99)
    if wide != "[\n          1\n]": return panic("indent clamps at ten")

    let negative: Result[String, JsonError] = error(JsonError.InvalidInput)
    if stringify(1, indent: -1) != negative: return panic("negative indent")

interface Named:
    fn label() String

type Person:
    name: String

impl Named for Person:
    fn label() String:
        return self.name

type Holder:
    who: Named
    at: Instant
    done: Unit

test "JSON stringify omits interface values and monotonic instants":
    let who = Named(Person("p"))
    let holder = Holder(who, clock().now(), unit)
    if (try encoded(holder)) != "\{\}": return panic(
        "interface and instant fields have no JSON form"
    )

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    if stringify(clock().now()) != invalid: return panic("root instant")
    if stringify(unit) != invalid: return panic("root unit")

    let failed: Result[Int, JsonError] = error(JsonError.LimitExceeded)
    if (try encoded(failed)) != "\{\"error\":\{\"cause\":\"LimitExceeded\"\}\}": return panic(
        "result error payload"
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
    let fields = Map[String, JsonValue]().add("type", JsonValue.StringValue(kind))
    let all = fields.add("id", JsonValue.NumberValue("{id}"))
    return JsonValue.ObjectValue(all)

type Feed:
    events: List[Event]

test "JSON stringify lets JsonEncode override the structural encoding of an alternative":
    if (try encoded(Event.Created(1))) != "\{\"type\":\"created\",\"id\":1\}": return panic(
        "custom tagged alternative"
    )

    let feed = Feed([Event.Created(1), Event.Deleted(2)])
    let expected = "\{\"events\":[\{\"type\":\"created\",\"id\":1\},\{\"type\":\"deleted\",\"id\":2\}]\}"
    if (try encoded(feed)) != expected: return panic(
        "custom encoding nested in a record"
    )

type Change:
    case Added(id: Int)
    case Removed(id: Int)

test "JSON stringify keeps cases with identical labels distinct by default":
    if (try encoded(Change.Added(1))) != "\{\"Added\":\{\"id\":1\}\}": return panic(
        "tagged Added"
    )
    if (try encoded(Change.Removed(1))) != "\{\"Removed\":\{\"id\":1\}\}": return panic(
        "tagged Removed"
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

fn decoded[T](text: String) Result[T, JsonError]:
    return parse[T](text)

test "JSON parse decodes records by field name with defaults and optional fields":
    let text = "\{\"scores\":[1,2.5],\"name\":\"Ada\",\"labels\":\{\"a\":1\},\"ids\":[3,3,4]\}"
    let profile: Profile = try parse[Profile](text)
    if profile.name != "Ada": return panic("record field")
    if profile.age != 18: return panic("field default")
    if not profile.nickname.is_none(): return panic("missing optional is none")
    if profile.scores.length() != 2 or profile.scores.at(1).get() != 2.5: return panic(
        "float list"
    )
    if profile.labels.get("a").get() != 1: return panic("map member")
    if profile.ids.length() != 2: return panic("set drops repeats")

    let full = "\{\"name\":\"B\",\"age\":30,\"nickname\":\"bee\",\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    let other: Profile = try parse[Profile](full)
    if other.age != 30 or other.nickname.get() != "bee": return panic("present members")

test "JSON parse rejects shape mismatches as InvalidData":
    let invalid: Result[Profile, JsonError] = error(JsonError.InvalidData)
    let missing = "\{\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    if parse[Profile](missing) != invalid: return panic("missing required field")

    let unknown = "\{\"name\":\"A\",\"scores\":[],\"labels\":\{\},\"ids\":[],\"extra\":1\}"
    if parse[Profile](unknown, ignore_unknown_fields: false) != invalid: return panic(
        "unknown member in strict mode"
    )

    let lenient: Profile = try parse[Profile](unknown)
    if lenient.name != "A": return panic("unknown members are ignored by default")

    let wrong = "\{\"name\":1,\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    if parse[Profile](wrong) != invalid: return panic("wrong member type")

    let fractional = "\{\"name\":\"A\",\"age\":1.5,\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    if parse[Profile](fractional) != invalid: return panic("fraction is not an Int")

    let overflow = "\{\"name\":\"A\",\"age\":9223372036854775808,\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    if parse[Profile](overflow) != invalid: return panic("Int overflow")
    if parse[Profile]("[]") != invalid: return panic("array is not a record")

    let malformed: Result[Profile, JsonError] = error(JsonError.InvalidData)
    if parse[Profile]("\{") != malformed: return panic("syntax errors stay InvalidData")

    let limited: Result[Profile, JsonError] = error(JsonError.LimitExceeded)
    if parse[Profile](missing, JsonLimits(2)) != limited: return panic(
        "limits apply before decoding"
    )

test "JSON parse decodes alternatives and generic records":
    let shape: Shape = try parse[Shape]("\"Dot\"")
    if shape != Shape.Dot: return panic("case without payload")

    let circle: Shape = try parse[Shape]("\{\"Circle\":\{\"radius\":2\}\}")
    if circle != Shape.Circle(2): return panic("case with payload")

    let invalid: Result[Shape, JsonError] = error(JsonError.InvalidData)
    if parse[Shape]("\"Circle\"") != invalid: return panic(
        "payload case needs its fields"
    )
    if parse[Shape]("\{\"Dot\":\{\}\}") != invalid: return panic(
        "payload on a nullary case"
    )
    if parse[Shape]("\"Square\"") != invalid: return panic("unknown case")
    if parse[Shape]("\{\"Circle\":\{\"radius\":1\},\"Dot\":\{\}\}") != invalid: return panic(
        "two cases"
    )

    let scene: Scene = try parse[Scene](
        "\{\"shape\":\"Dot\",\"shapes\":[\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
    )
    if scene.shapes.at(0).get() != Shape.Rect(1, 2): return panic("nested alternative")

    let wrapper: Wrapper[Int] = try parse[Wrapper[Int]]("\{\"first\":1\}")
    if wrapper.first != 1 or not wrapper.second.is_none() or wrapper.extra != 7: return panic(
        "generic record"
    )

    let nested: Wrapper[Wrapper[String]] = try parse[Wrapper[Wrapper[String]]](
        "\{\"first\":\{\"first\":\"x\",\"extra\":1\},\"second\":null\}"
    )
    if nested.first.first != "x" or nested.first.extra != 1 or nested.extra != 7: return panic(
        "nested generic record with defaults"
    )

test "JSON parse decodes recursive types exact numbers and passthrough values":
    let tree: Tree = try parse[Tree](
        "\{\"label\":\"r\",\"children\":[\{\"label\":\"c\",\"children\":[]\}]\}"
    )
    if tree.children.at(0).get().label != "c": return panic("recursive record")

    let price: Price = try parse[Price](
        "\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
    )
    let price_text: Result[String, JsonError] = ok(
        "\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
    )
    if stringify(price) != price_text: return panic("exact numbers round trip")

    let raw = try parse("\{\"n\":1.50\}")
    let boxed: Wrapper[JsonValue] = try parse[Wrapper[JsonValue]](
        "\{\"first\":\{\"n\":1.50\}\}"
    )
    if boxed.first != raw: return panic("JsonValue keeps its subtree")

    let list: List[Optional[Int]] = try parse[List[Optional[Int]]]("[1,null]")
    if list.at(1).get().is_some(): return panic("null element is none")

test "JSON parse inverts stringify and works in generic code":
    let profile = Profile(
        "Ada",
        20,
        some("a"),
        [0.5],
        Map[String, Int]().add("k", 1),
        Set[Int]().add(2)
    )
    let text = try stringify(profile)
    let again: Profile = try decoded[Profile](text)
    if (try stringify(again)) != text: return panic("round trip")
    if again.nickname.get() != "a": return panic("optional round trip")

    let shapes: List[Shape] = [Shape.Dot, Shape.Rect(3, 4)]
    let shapesBack: List[Shape] = try decoded[List[Shape]](try stringify(shapes))
    if shapesBack.at(1).get() != Shape.Rect(3, 4): return panic(
        "alternative round trip"
    )

fn load_profile(text: String) Result[Profile, JsonError]:
    let profile = try parse[Profile](text)
    return ok(profile)

fn load_default(text: String) Result[JsonValue, JsonError]:
    return parse(text)

test "JSON parse takes its type from an explicit argument, the expected result or the JsonValue default":
    let profile = try load_profile(
        "\{\"name\":\"Ada\",\"scores\":[],\"labels\":\{\},\"ids\":[]\}"
    )
    if profile.name != "Ada": return panic("try keeps the explicit type")

    let invalid: Result[Profile, JsonError] = error(JsonError.InvalidData)
    if load_profile("\{\"name\":1\}") != invalid: return panic(
        "try propagates the decode error"
    )

    let raw = try load_default("\{\"a\":[1]\}")
    let again = try parse("\{\"a\":[1]\}")
    if raw != again: return panic("default keeps the parsed tree")

test "JSON parse reads what stringify writes for standard values and scalar map keys":
    let at = try timestamp(1700000000, 500000000)
    let link = Url("https", "example.com", some(8080), "/a", "x=1", "")
    let item = Stamped(at, duration(1500), "hi".to_bytes(), link)
    let text = try stringify(item)
    let back: Stamped = try parse[Stamped](text)
    if (try stringify(back)) != text: return panic("standard values round trip")
    if back.took != duration(1500): return panic("duration nanoseconds")

    let ints: Map[Int, String] = try parse[Map[Int, String]](
        "\{\"2\":\"b\",\"1\":\"a\"\}"
    )
    if ints.get(2).get() != "b": return panic("Int keys decode")

    let bad: Result[Map[Int, String], JsonError] = error(JsonError.InvalidData)
    if parse[Map[Int, String]]("\{\"x\":\"b\"\}") != bad: return panic(
        "unparsable key is InvalidData"
    )

    let flags: Map[Bool, Int] = try parse[Map[Bool, Int]]("\{\"true\":1\}")
    if flags.get(true).get() != 1: return panic("Bool keys decode")

    let kinds: Map[Tagged, Int] = try parse[Map[Tagged, Int]]("\{\"Plain\":3\}")
    if kinds.get(Tagged.Plain).get() != 3: return panic("payloadless case keys decode")

test "JSON parse needs a default for fields without a JSON form":
    let outcome = parse[Handler]("\{\"name\":\"n\"\}")
    if outcome.is_ok(): return panic("function field is required")

test "JSON parse reads standard alternatives and rejects keys that collide":
    let good: Result[Int, JsonError] = try parse[Result[Int, JsonError]](
        "\{\"ok\":\{\"value\":5\}\}"
    )
    let want_ok: Result[Int, JsonError] = ok(5)
    if good != want_ok: return panic("Result ok reads back")

    let failed: Result[Int, JsonError] = try parse[Result[Int, JsonError]](
        "\{\"error\":\{\"cause\":\"InvalidData\"\}\}"
    )
    let want_error: Result[Int, JsonError] = error(JsonError.InvalidData)
    if failed != want_error: return panic("Result error reads back")

    let kind: JsonError = try parse[JsonError]("\"LimitExceeded\"")
    if kind != JsonError.LimitExceeded: return panic("payloadless standard case")

    let collide: Result[Map[Int, String], JsonError] = error(JsonError.InvalidData)
    if parse[Map[Int, String]]("\{\"1\":\"a\",\"01\":\"b\"\}") != collide: return panic(
        "1 and 01 are one Int key"
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
    var head = Link(none, 0)
    for i in range(1, 300000):
        head = Link(some(head), i)
    let r = stringify(head)
    if r.is_ok(): return panic("nesting beyond the parse ceiling must fail")

test "JSON parse runs field defaults that read earlier fields":
    let d = try parse[Defaults]("\{\"a\":5\}")
    if d.b != 6 or d.c != "x6": return panic("default chain {d.b} {d.c}")

test "JSON round trips fields named like Go keywords":
    let k = Kw(1, 2, 3)
    let t = try stringify(k)
    let back = try parse[Kw](t)
    if back.range != 3: return panic(t)

test "JSON round trips generic records alternatives and Duration keys":
    let w = Wrap(
        [Op.Add(1, 2), Op.Neg(none), Op.Neg(some(3)), Op.Nop],
        [Pair(1, Op.Nop)],
        Map[Duration, String]().add(duration(5), "five")
    )
    let t = try stringify(w)
    let back = try parse[Wrap](t)
    if (try stringify(back)) != t: return panic(t)

test "JSON parse returns InvalidData for targets that cannot be read":
    if parse[Unit]("null").is_ok(): return panic("unit")

    let f = parse[fn() Int]("1")
    if f.is_ok(): return panic("fn")
    if parse[Int]("-0").is_error(): return panic("-0")
    if parse[Float]("1e999").is_ok(): return panic("inf")
    if parse[String]("1").is_ok(): return panic("str")
    if parse[List[Int]]("[1,\"a\"]").is_ok(): return panic("elem")
