import (
	Bytes from "@std/bytes.ms",
	Data from "@std/core.ms",
	JsonEncode,
	JsonOptions,
	JsonValue,
	StringifyOptions,
	parse,
	stringify from "@std/data/json.ms",
	Decimal from "@std/math/decimal.ms",
	BigInt from "@std/math/math.ms",
	Url from "@std/net/url.ms",
	expect_contains,
	expect_equal,
	expect_error,
	expect_false,
	expect_not_equal,
	fail from "@std/test/test.ms",
	Duration, Instant, Timestamp, nanoseconds, timestamp from "@std/time.ms",
)

test "JSON exact numbers Unicode and nested roundtrip":
	text := "\{\"n\":9007199254740993,\"s\":\"é🙂\",\"a\":[null,true,false]\}"
	expect_equal((parse(text)? | stringify?), text)?
	expect_equal((parse("\"\\uD83D\\uDE00\"")?), JsonValue.StringValue("😀"))?
	expect_equal((parse("null")? | stringify(StringifyOptions(max_bytes: 4))?), "null")?

fn expect_syntax_error[T](actual: T!) Unit!:
	cause := expect_error(actual)?
	expect_equal(cause.kind, "EBADMSG")?
	expect_contains(cause.message, "JSON: invalid data: line ")?

fn expect_invalid_data[T](actual: T!) Unit!:
	cause := expect_error(actual)?
	expect_equal(cause.kind, "EBADMSG")?
	expect_contains(cause.message, "JSON: invalid data")?

test "JSON decode errors name the failing path":
	wrong := parse[Profile]("\{\"name\":1\}")
	expect_equal(
		(expect_error(wrong)?).message,
		"JSON: invalid data: at $.name: expected string, found number"
	)?

	nested := parse[List[Profile]]("[\{\"name\":\"a\",\"scores\":[]\}, 3]")
	expect_contains(
		(expect_error(nested)?).message, "at $[1]: expected object, found number"
	)?

test "JSON rejects duplicate keys malformed Unicode and trailing values":
	for text in [
		"\{\"a\":1,\"\\u0061\":2\}", "\"\\uD800\"", "\"\\uDC00\"", "1 2", "NaN", "[1,]"
	]:
		expect_syntax_error(parse(text))?

test "JSON independently enforces byte depth and value budgets":
	limited: JsonValue! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(parse("null", JsonOptions(max_bytes: 3)), limited)?
	expect_equal(parse("[[[]]]", JsonOptions(max_depth: 2)), limited)?
	expect_equal(parse("[1,2]", JsonOptions(max_values: 2)), limited)?

	invalid: JsonValue! := error(Error("JSON: invalid input", kind: "EINVAL"))
	expect_equal(parse("null", JsonOptions(max_bytes: -1)), invalid)?

test "JSON untyped parse keeps document shape and releases partial trees on failure":
	long := "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
	text := (
		"[\{\""
		+ long
		+ "\":[1,\""
		+ long
		+ "\",\{\}],\"k\\n\":null\},[],true,-1.5e3,\"\\u00e9\"]"
	)
	parsed := parse(text)?
	expect_equal(stringify(parsed)?, text.replace("\\u00e9", "é"))?

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
	expect_syntax_error(parse(wide + "\"k7\":0\}"))?
	expect_syntax_error(parse(wide + "\"k40\":["))?

	fine := parse(wide + "\"k40\":0\}")?
	expect_equal(stringify(fine)?, wide + "\"k40\":0\}")?

test "JSON stringify rejects number text with trailing whitespace":
	padded: String! := error(Error("JSON: invalid data", kind: "EBADMSG"))
	expect_equal(stringify(JsonValue.NumberValue("1\n")), padded)?
	expect_equal(stringify(JsonValue.NumberValue("1 ")), padded)?

test "JSON parse bounds nesting even without a depth limit":
	var text = ""
	var closing = ""

	for i in 0..150000:
		text += "["
		closing += "]"

	limited: JsonValue! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(parse(text + closing), limited)?

type Request:
	model: String
	stream: Bool
	user: String?
	temperature: Float
	tags: List[String]

enum Shape:
	Circle(radius: Int)
	Rect(width: Int, height: Int)
	Dot

type Scene:
	shape: Shape
	shapes: List[Shape]
	note: String?

type Box[T]:
	first: T
	second: T?

type Node:
	label: String
	next: Node?

fn encoded[T: Data](item: T) String!:
	return stringify(item)

test "JSON stringify encodes records in declaration order and omits none fields":
	var request = Request("m", stream: true, none, 0.5, ["a", "b"])
	expected := "\{\"model\":\"m\",\"stream\":true,\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
	expect_equal((encoded(request)?), expected)?
	request.user = "u"

	named := "\{\"model\":\"m\",\"stream\":true,\"user\":\"u\",\"temperature\":0.5,\"tags\":[\"a\",\"b\"]\}"
	expect_equal((encoded(request)?), named)?
	expect_equal((encoded(Box[Int](1, none))?), "\{\"first\":1\}")?
	expect_equal((encoded(Box[Int](1, 2))?), "\{\"first\":1,\"second\":2\}")?

test "JSON stringify encodes alternatives and nested optionals":
	scene := Scene(Shape.Circle(2), [Shape.Dot, Shape.Rect(1, 2)], none)
	expected := "\{\"shape\":\{\"Circle\":\{\"radius\":2\}\},\"shapes\":[\"Dot\",\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
	expect_equal((encoded(scene)?), expected)?

	sparse: List[Int?] := [1, none]
	expect_equal((encoded(sparse)?), "[1,null]")?

	missing: Int? := none
	expect_equal((encoded(missing)?), "null")?

test "JSON stringify encodes scalars exactly":
	expect_equal((encoded(9007199254740993)?), "9007199254740993")?
	expect_equal((encoded(1.0)?), "1")?
	expect_equal((encoded(0.1)?), "0.1")?
	expect_equal((encoded(1e300)?), "1e+300")?
	expect_equal((encoded("<é\n")?), "\"<é\\n\"")?

	parsed := parse("\{\"n\":1.50\}")?
	mixed := Box[JsonValue](parsed, none)
	expect_equal((encoded(mixed)?), "\{\"first\":\{\"n\":1.50\}\}")?

test "JSON stringify reports non-finite numbers and budgets as errors":
	expect_equal((encoded(1e308 * 10.0)?), "null")?
	expect_equal((encoded(1e308 * 10.0 - 1e308 * 10.0)?), "null")?

	limited: String! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(stringify("abcdef", StringifyOptions(max_bytes: 4)), limited)?

	negative: String! := error(Error("JSON: invalid input", kind: "EINVAL"))
	expect_equal(stringify(1, StringifyOptions(max_bytes: -1)), negative)?

test "JSON stringify repeats shared acyclic values and reads current field values":
	shared := Node("s", none)
	var pair = [shared.clone(), shared.clone()]
	before := encoded(pair)?
	pair.set(0, Node("changed", none))
	expect_equal(before, "[\{\"label\":\"s\"\},\{\"label\":\"s\"\}]")?
	expect_not_equal((encoded(pair)?), before)?

type Handler:
	name: String
	retries: Int??
	note: String?

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

enum Tagged:
	Named(name: String, alias: String?)
	Plain

test "JSON stringify omits none fields and keeps nested optionals":
	var handler = Handler("h", none, none)
	expect_equal((encoded(handler)?), "\{\"name\":\"h\"\}")?

	inner_none: Int? := none
	handler.retries = inner_none
	expect_equal((encoded(handler)?), "\{\"name\":\"h\",\"retries\":null\}")?

	inner_three: Int? := 3
	handler.retries = inner_three
	expect_equal((encoded(handler)?), "\{\"name\":\"h\",\"retries\":3\}")?

test "JSON stringify encodes standard-library values":
	at := timestamp(1700000000, 500000000)?
	link := Url("https", "example.com", 8080, "/a", "x=1", "")
	item := Stamped(at, nanoseconds(1500), "hi".to_bytes(), link)
	expected := "\{\"at\":\"2023-11-14T22:13:20.5Z\",\"took\":1500,\"data\":\"aGk=\",\"link\":\"https://example.com:8080/a?x=1\"\}"
	expect_equal((encoded(item)?), expected)?
	expect_equal((encoded(Error("boom"))?), "\{\"message\":\"boom\",\"details\":\{\}\}")?

	ok: Int! := ok(5)
	expect_equal((encoded(ok)?), "\{\"ok\":\{\"value\":5\}\}")?
	expect_equal((encoded("EBADMSG")?), "\"EBADMSG\"")?
	expect_equal(
		(encoded(Tagged.Named("n", none))?), "\{\"Named\":\{\"name\":\"n\"\}\}"
	)?
	expect_equal((encoded(Tagged.Plain)?), "\"Plain\"")?

test "JSON stringify honors JsonEncode wherever the value appears":
	invoice := Invoice(Money(500), [Money(200), Money(300)])
	expected := "\{\"total\":\"usd:500\",\"lines\":[\"usd:200\",\"usd:300\"]\}"
	expect_equal((encoded(invoice)?), expected)?
	expect_equal((encoded(Money(7))?), "\"usd:7\"")?

test "JSON stringify indents like JSON.stringify and clamps at ten":
	request := Request("m", stream: true, none, 0.5, ["a"])
	pretty := stringify(request, StringifyOptions(indent: 2))?
	expected := "\{\n  \"model\": \"m\",\n  \"stream\": true,\n  \"temperature\": 0.5,\n  \"tags\": [\n    \"a\"\n  ]\n\}"
	expect_equal(pretty, expected)?

	empty: List[Int] := []
	expect_equal((stringify(empty, StringifyOptions(indent: 4))?), "[]")?
	expect_equal((stringify([1], StringifyOptions(indent: 0))?), "[1]")?

	wide := stringify([1], StringifyOptions(indent: 99))?
	expect_equal(wide, "[\n          1\n]")?

	negative: String! := error(Error("JSON: invalid input", kind: "EINVAL"))
	expect_equal(stringify(1, StringifyOptions(indent: -1)), negative)?

type Holder:
	done: Unit

test "JSON stringify omits a Unit field and rejects a Unit root":
	holder := Holder(unit)
	expect_equal((encoded(holder)?), "\{\}")?

	invalid: String! := error(Error("JSON: invalid data", kind: "EBADMSG"))
	expect_equal(stringify(unit), invalid)?

	failed: Int! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(
		(encoded(failed)?),
		"\{\"error\":\{\"cause\":\{\"message\":\"JSON: limit exceeded\",\"kind\":\"EOVERFLOW\",\"details\":\{\}\}\}\}"
	)?

enum Event:
	Created(id: Int)
	Deleted(id: Int)

impl JsonEncode for Event:
	fn to_json() JsonValue:
		match self:
			Created(id): return tagged("created", id)
			Deleted(id): return tagged("deleted", id)

fn tagged(kind: String, id: Int) JsonValue:
	var fields = Map[String, JsonValue]()
	fields.add("type", JsonValue.StringValue(kind))
	fields.add("id", JsonValue.NumberValue("{id}"))

	all := fields
	return JsonValue.ObjectValue(all)

type Feed:
	events: List[Event]

test "JSON stringify lets JsonEncode override the structural encoding of an alternative":
	expect_equal((encoded(Event.Created(1))?), "\{\"type\":\"created\",\"id\":1\}")?

	feed := Feed([Event.Created(1), Event.Deleted(2)])
	expected := "\{\"events\":[\{\"type\":\"created\",\"id\":1\},\{\"type\":\"deleted\",\"id\":2\}]\}"
	expect_equal((encoded(feed)?), expected)?

enum Change:
	Added(id: Int)
	Removed(id: Int)

test "JSON stringify keeps cases with identical labels distinct by default":
	expect_equal((encoded(Change.Added(1))?), "\{\"Added\":\{\"id\":1\}\}")?
	expect_equal((encoded(Change.Removed(1))?), "\{\"Removed\":\{\"id\":1\}\}")?

type Profile:
	name: String
	age: Int = 18
	nickname: String?
	scores: List[Float]

type Wrapper[T]:
	first: T
	second: T?
	extra: Int = 7

type Tree:
	label: String
	children: List[Tree]

type Price:
	amount: Decimal
	cents: BigInt

fn decoded[T: Data](text: String) T!:
	return parse[T](text)

test "JSON parse decodes records by field name with defaults and optional fields":
	text := "\{\"scores\":[1,2.5],\"name\":\"Ada\",\"extra\":1\}"
	profile: Profile := parse[Profile](text)?
	expect_equal(profile.name, "Ada")?
	expect_equal(profile.age, 18)?
	expect_false(profile.nickname.is_some())?
	expect_false(profile.scores.length() != 2 or profile.scores.get(1) != 2.5)?

	full := "\{\"name\":\"B\",\"age\":30,\"nickname\":\"bee\",\"scores\":[]\}"
	other: Profile := parse[Profile](full)?
	expect_false(other.age != 30 or other.nickname.get() != "bee")?

test "JSON parse rejects shape mismatches as InvalidData":
	missing := "\{\"scores\":[]\}"
	expect_invalid_data(parse[Profile](missing))?

	unknown := "\{\"name\":\"A\",\"scores\":[],\"extra\":1\}"
	expect_invalid_data(
		parse[Profile](unknown, JsonOptions(ignore_unknown_fields: false))
	)?

	lenient: Profile := parse[Profile](unknown)?
	expect_equal(lenient.name, "A")?

	wrong := "\{\"name\":1,\"scores\":[]\}"
	expect_invalid_data(parse[Profile](wrong))?

	fractional := "\{\"name\":\"A\",\"age\":1.5,\"scores\":[]\}"
	expect_invalid_data(parse[Profile](fractional))?

	overflow := "\{\"name\":\"A\",\"age\":9223372036854775808,\"scores\":[]\}"
	expect_invalid_data(parse[Profile](overflow))?
	expect_invalid_data(parse[Profile]("[]"))?
	expect_syntax_error(parse[Profile]("\{"))?

	limited: Profile! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(parse[Profile](missing, JsonOptions(max_bytes: 2)), limited)?

test "JSON parse decodes alternatives and generic records":
	shape: Shape := parse[Shape]("\"Dot\"")?
	expect_equal(shape, Shape.Dot)?

	circle: Shape := parse[Shape]("\{\"Circle\":\{\"radius\":2\}\}")?
	expect_equal(circle, Shape.Circle(2))?
	expect_invalid_data(parse[Shape]("\"Circle\""))?
	expect_invalid_data(parse[Shape]("\{\"Dot\":\{\}\}"))?
	expect_invalid_data(parse[Shape]("\"Square\""))?
	expect_invalid_data(parse[Shape]("\{\"Circle\":\{\"radius\":1\},\"Dot\":\{\}\}"))?

	scene: Scene := parse[Scene](
		"\{\"shape\":\"Dot\",\"shapes\":[\{\"Rect\":\{\"width\":1,\"height\":2\}\}]\}"
	)?
	expect_equal(scene.shapes.get(0), Shape.Rect(1, 2))?

	wrapper: Wrapper[Int] := parse[Wrapper[Int]]("\{\"first\":1\}")?
	expect_false((wrapper.first != 1 or wrapper.second.is_some() or wrapper.extra != 7))?

	nested: Wrapper[Wrapper[String]] := parse[Wrapper[Wrapper[String]]](
		"\{\"first\":\{\"first\":\"x\",\"extra\":1\},\"second\":null\}"
	)?
	expect_false(
		(
			nested.first.first != "x"
			or nested.first.extra != 1
			or nested.extra != 7
		)
	)?

test "JSON parse decodes recursive types exact numbers and passthrough values":
	tree: Tree := parse[Tree](
		"\{\"label\":\"r\",\"children\":[\{\"label\":\"c\",\"children\":[]\}]\}"
	)?
	expect_equal(tree.children.get(0).label, "c")?

	price: Price := parse[Price](
		"\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
	)?
	price_text: String! := ok(
		"\{\"amount\":1.5,\"cents\":123456789012345678901234567890\}"
	)
	expect_equal(stringify(price), price_text)?

	raw := parse("\{\"n\":1.50\}")?
	boxed: Wrapper[JsonValue] := parse[Wrapper[JsonValue]](
		"\{\"first\":\{\"n\":1.50\}\}"
	)?
	expect_equal(boxed.first, raw)?

	list: List[Int?] := parse[List[Int?]]("[1,null]")?
	expect_false(list.get(1).is_some())?

test "JSON parse inverts stringify and works in generic code":
	profile := Profile("Ada", 20, "a", [0.5])
	text := stringify(profile)?
	again: Profile := decoded[Profile](text)?
	expect_equal((stringify(again)?), text)?
	expect_equal(again.nickname.get(), "a")?

	shapes: List[Shape] := [Shape.Dot, Shape.Rect(3, 4)]
	shapesBack: List[Shape] := decoded[List[Shape]](stringify(shapes)?)?
	expect_equal(shapesBack.get(1), Shape.Rect(3, 4))?

fn load_profile(text: String) Profile!:
	profile := parse[Profile](text)?
	return ok(profile)

fn load_default(text: String) JsonValue!:
	return parse(text)

test "JSON parse takes its type from an explicit argument, the expected result or the JsonValue default":
	profile := load_profile("\{\"name\":\"Ada\",\"scores\":[]\}")?
	expect_equal(profile.name, "Ada")?
	expect_invalid_data(load_profile("\{\"name\":1\}"))?

	raw := load_default("\{\"a\":[1]\}")?
	again := parse("\{\"a\":[1]\}")?
	expect_equal(raw, again)?

test "JSON parse reads what stringify writes for standard values and scalar map keys":
	at := timestamp(1700000000, 500000000)?
	link := Url("https", "example.com", 8080, "/a", "x=1", "")
	item := Stamped(at, nanoseconds(1500), "hi".to_bytes(), link)
	text := stringify(item)?
	back: Stamped := parse[Stamped](text)?
	expect_equal((stringify(back)?), text)?
	expect_equal(back.took, nanoseconds(1500))?

test "JSON parse reads standard alternatives and rejects keys that collide":
	good: Int! := parse[Int!]("\{\"ok\":\{\"value\":5\}\}")?
	want_ok: Int! := ok(5)
	expect_equal(good, want_ok)?

	failed: Int! := parse[Int!](
		"\{\"error\":\{\"cause\":\{\"message\":\"bad\",\"kind\":\"EBADMSG\",\"details\":\{\}\}\}\}"
	)?
	want_error: Int! := error(Error("bad", kind: "EBADMSG"))
	expect_equal(failed, want_error)?

	kind: String := parse[String]("\"EOVERFLOW\"")?
	expect_equal(kind, "EOVERFLOW")?

type Link:
	next: Link?
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

enum Op:
	Add(left: Int, right: Int)
	Neg(v: Int?)
	Nop

type Wrap:
	ops: List[Op]
	pairs: List[Pair[Int, Op]]

test "JSON stringify fails on nesting deeper than parse accepts":
	var head = Link(none, 0)
	for i in 1..300000:
		head = Link(head, i)

	r := stringify(head)
	expect_false(r.is_ok())?

test "JSON parse runs field defaults that read earlier fields":
	d := parse[Defaults]("\{\"a\":5\}")?
	if d.b != 6 or d.c != "x6": return fail("default chain {d.b} {d.c}")

test "JSON round trips fields named like Go keywords":
	k := Kw(1, 2, 3)
	t := stringify(k)?
	back := parse[Kw](t)?
	expect_equal(back.range, 3)?

test "JSON round trips generic records and alternatives":
	w := Wrap([Op.Add(1, 2), Op.Neg(none), Op.Neg(3), Op.Nop], [Pair(1, Op.Nop)])
	t := stringify(w)?
	back := parse[Wrap](t)?
	expect_equal((stringify(back)?), t)?

test "JSON parse returns InvalidData for targets that cannot be read":
	expect_false(parse[Unit]("null").is_ok())?
	expect_false(parse[Int]("-0").is_error())?
	expect_false(parse[Float]("1e999").is_ok())?
	expect_false(parse[String]("1").is_ok())?
	expect_false(parse[List[Int]]("[1,\"a\"]").is_ok())?

type BoundReading:
	id: Int

test "JSON parse and stringify bound to a type argument pipe like the call":
	read := parse[List[BoundReading]]
	write := stringify[BoundReading]
	items := "[\{\"id\":1\},\{\"id\":2\}]" | read
	expect_equal(items, ok([BoundReading(1), BoundReading(2)]))?
	expect_equal(BoundReading(1) | write, ok("\{\"id\":1\}"))?

test "JSON Decimal fields out of range or inexact are InvalidData":
	tiny := "\{\"amount\":1e-9990,\"cents\":1\}"
	expect_invalid_data(parse[Price](tiny))?

	huge := "\{\"amount\":1e9990,\"cents\":1\}"
	expect_invalid_data(parse[Price](huge))?

	wide := "\{\"amount\":0.1234567890123456789012345678901234567890,\"cents\":1\}"
	expect_invalid_data(parse[Price](wide))?
