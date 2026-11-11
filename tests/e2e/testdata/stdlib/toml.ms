import (
	TomlOptions, TomlValue, parse, stringify from "@std/data/toml.ms",
	expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test/test.ms",
	monotonic from "@std/time.ms",
)

fn entries(value: TomlValue) Map[String, TomlValue]!:
	match value:
		TableValue(values): return ok(values)
		_: return error(Error("expected TOML table"))

fn items(value: TomlValue) List[TomlValue]!:
	match value:
		ArrayValue(values): return ok(values)
		_: return error(Error("expected TOML array"))

fn limits(bytes: Int?, depth: Int?, values: Int?) TomlOptions:
	return TomlOptions(max_bytes: bytes, max_depth: depth, max_values: values)

test "TOML scalars quoted keys comments exact integers and dates":
	source := "title = \"é🙂 # text\" # comment\n'' = 'literal\\n'\nbool = true\nlarge = 9007199254740993\nhex = 0xDEAD_BEEF\noct = 0o755\nbin = 0b1010\nfloat = -1_2.5e+2\ndate = 2024-02-29\ntime = 07:32:00.123\nstamp = 1979-05-27 07:32:00-07:00\n"
	root := parse(text: source) | expect_ok? | entries?
	(root["title"] | expect_equal(TomlValue.StringValue("é🙂 # text"))?)
	root[""] | expect_equal(TomlValue.StringValue("literal\\n"))?
	root["large"] | expect_equal(TomlValue.IntValue(9007199254740993))?
	root["hex"] | expect_equal(TomlValue.IntValue(3735928559))?
	root["oct"] | expect_equal(TomlValue.IntValue(493))?
	root["bin"] | expect_equal(TomlValue.IntValue(10))?
	root["float"] | expect_equal(TomlValue.FloatValue(-1250.0))?
	expect_false(
		(root["stamp"] != TomlValue.DateTimeValue("1979-05-27 07:32:00-07:00"))
	)?
	root["date"] | expect_equal(TomlValue.DateTimeValue("2024-02-29"))?
	root["time"] | expect_equal(TomlValue.DateTimeValue("07:32:00.123"))?

test "TOML multiline strings Unicode escapes arrays and inline tables":
	root := (
		entries(
			(
				parse(
					text: "basic = \"\"\"\nhello \\\n    world\\u0021\"\"\"\nliteral = '''\nraw\\text\nnext'''\narray = [1, # first\n true, \{name = 'Ada', meta.age = 37\},]\n"
				) | expect_ok?
			)
		)?
	)
	root["basic"] | expect_equal(TomlValue.StringValue("hello world!"))?
	root["literal"] | expect_equal(TomlValue.StringValue("raw\\text\nnext"))?

	array := (items(root.get("array").get())?)
	array.length() | expect_equal(3)?

	person := (entries(array.get(2).clone())?)
	person["name"] | expect_equal(TomlValue.StringValue("Ada"))?
	expect_false(
		(
			(entries(person.get("meta").get())?).get(
				"age"
			).get() != TomlValue.IntValue(37)
		)
	)?

test "TOML implicit parents dotted keys and arrays of tables":
	text := "[owner.details]\nname = 'Ada'\n[owner]\nactive = true\n[[products]]\nname = 'Hammer'\n[products.meta]\nstock = 3\n[[products]]\nname = 'Nail'\n[[products.variants]]\nsize = 1\n[[products.variants]]\nsize = 2\n"
	root := parse(text: text) | expect_ok? | entries?
	owner := (entries(root.get("owner").get())?)
	expect_false(
		(
			(entries(owner.get("details").get())?).get(
				"name"
			).get() != TomlValue.StringValue("Ada")
		)
	)?

	products := (items(root.get("products").get())?)
	products.length() | expect_equal(2)?
	expect_false(
		(
			(
				entries(
					(entries(products.first().get())?).get(
						"meta"
					).get()
				)?
			)["stock"] != TomlValue.IntValue(3)
		)
	)?
	(items((entries(products.last().get())?)["variants"])?).length() | expect_equal(2)?

	dotted := parse(text: "a.b.c = 1\na.b.d = 2\n") | expect_ok? | entries?
	(entries((entries(dotted.get("a").get())?).get("b").get())?).length() | expect_equal(
		2
	)?

test "TOML parses a long array of tables in order":
	var source = ""
	for i in 0..30000:
		source += "[[items]]\nid = {i}\n"

	root := parse(text: source) | expect_ok? | entries?
	rows := items(root.get("items").get())?
	rows.length() | expect_equal(30000)?

	last := entries(rows.get(29999).clone())?
	last["id"] | expect_equal(TomlValue.IntValue(29999))?

test "TOML dotted extensions define existing implicit parents":
	for text in [
		"[a.b.c]\n[a]\nb.d=2\n[a.b]", "[a.b.c.d]\n[a]\nb.c.e=2\n[a.b]",
		"[a.b.c.d]\n[a]\nb.c.e=2\n[a.b.c]",
		"[a.'odd.key'.c]\n[a]\n'odd.key'.d=2\n[a.'odd.key']",
		"[[items]]\n[items.a.b.c]\n[items.a]\nb.d=2\n[items.a.b]"
	]:
		result := parse(text)
		result.is_error() | expect_true?
		result.err().kind | expect_equal("EBADMSG")?

test "TOML dotted extensions keep sibling assignments and child headers valid":
	source := "[a.b.c]\nx=1\n[a]\nb.d=2\nb.e=3\n[a.b.f]\ny=4"
	expected := "[a.b]\nd=2\ne=3\n[a.b.c]\nx=1\n[a.b.f]\ny=4"
	parsed := parse(source) | expect_ok?
	parsed | expect_equal(parse(expected) | expect_ok?)?
	parse(stringify(parsed) | expect_ok?) | expect_ok? | expect_equal(parsed)?

test "TOML untouched implicit parents can still receive table headers":
	source := "[a.b.c]\nx=1\n[a.b]\ny=2\n[a]\nz=3"
	expected := "[a]\nz=3\n[a.b]\ny=2\n[a.b.c]\nx=1"
	parse(source) | expect_ok? | expect_equal(parse(expected) | expect_ok?)?

test "TOML rejects malformed data redefinitions and closed inline tables":
	for text in [
		"a=1\na=2", "[a]\n[a]", "a=1\n[a]", "a=\{b=1\}\na.c=2", "a.b=1\n[a]", "a=[1 2]",
		"a=[,]", "a=\{b=1,\}", "a=\{b=1\nb=2\}", "a=01", "a=1_", "a=_1", "a=1__2",
		"a=+0x1", "a=1.", "a=.1", "a=1e", "a=9223372036854775808", "a=2023-02-29",
		"a=24:00:00", "a='unterminated", "a=\"\\uD800\"", "a=\"\\q\"", "a=true false",
		"a=1\rb=2", "[a.b.c]\nz=9\n[a]\nb.c.t=1", "[[a.b]]\n[a]\nb.y=2"
	]:
		cause := match parse(text: text):
			ok(_): return fail("invalid TOML accepted: {text}")
			error(cause): cause

		cause.kind | expect_equal("EBADMSG")?
		cause.details["line"].parse_int().get() < 1 | expect_false?
		cause.details["column"].parse_int().get() < 1 | expect_false?
		((cause.message.starts_with("TOML ")) | expect_true?)

test "TOML optional limits include implicit tables and zero":
	limited: TomlValue! := error(Error("TOML limit exceeded", kind: "EOVERFLOW"))
	invalid: TomlValue! := error(Error("invalid TOML input", kind: "EINVAL"))
	expect_false(
		(
			parse(
				text: "a=1", options: limits(bytes: 2, depth: none, values: none)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "a.b=1", options: limits(bytes: none, depth: 2, values: none)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "a.b=1", options: limits(bytes: none, depth: none, values: 2)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "", options: limits(bytes: 0, depth: 1, values: 1)
			) != parse(text: "")
		)
	)?
	parse(text: "", options: limits(bytes: none, depth: none, values: 0)) | expect_equal(
		limited
	)?
	expect_false(
		(
			parse(
				text: "", options: limits(bytes: none, depth: -1, values: none)
			) != invalid
		)
	)?
	expect_false(
		(
			parse(
				text: "a=1", options: limits(bytes: 3, depth: 2, values: 2)
			) != parse(text: "a=1")
		)
	)?

test "TOML nonfinite floats CRLF and repeated separators":
	root := (
		entries(
			(
				parse(
					text: "positive=inf\r\nnegative=-inf\r\nnan=+nan\r\ninteger=1_000_000\r\n"
				) | expect_ok?
			)
		)?
	)

	match root["positive"]:
		FloatValue(number):
			((number.is_finite() or number < 0.0) | expect_false?)
		_: return fail("expected float")

	match root["negative"]:
		FloatValue(number):
			((number.is_finite() or number > 0.0) | expect_false?)
		_: return fail("expected float")

	match root["nan"]:
		FloatValue(number):
			((number.is_nan()) | expect_true?)
		_: return fail("expected float")

	root["integer"] | expect_equal(TomlValue.IntValue(1000000))?

fn failure(text: String) String:
	match parse(text: text):
		ok(_): return "accepted"
		error(cause): return cause.message

test "TOML errors report the offending line and column":
	failure("x = 1\ny = \"a\u{1}b\"") | expect_equal(
		"TOML 2:7: invalid control character"
	)?
	failure("x = 1\ny = 2\rz = 3") | expect_equal("TOML 2:6: bare carriage return")?
	failure("x = 1\n\u{0}") | expect_equal("TOML 2:1: invalid control character")?
	failure("a = 1\u{0}") | expect_equal("TOML 1:6: invalid control character")?
	failure("y = True") | expect_equal("TOML 1:5: invalid value")?
	failure("y = yes") | expect_equal("TOML 1:5: invalid value")?
	failure("y = abc") | expect_equal("TOML 1:5: invalid value")?
	failure("x = 1\ny = 1e") | expect_equal("TOML 2:5: invalid exponent")?

test "TOML option fields default to none or the depth and value guards":
	limited: TomlValue! := error(Error("TOML limit exceeded", kind: "EOVERFLOW"))
	parse(text: "a=1", options: TomlOptions(max_bytes: 2)) | expect_equal(limited)?
	parse(text: "a=1", options: TomlOptions()) | expect_equal(parse(text: "a=1"))?

test "TOML stringify round trips scalars tables and arrays of tables":
	source := "title = \"é🙂 \\\"q\\\" \\t tab\\u0001\"\nint = -42\nfloat = 3.0\nbig = 1e+21\nflag = true\ndate = 1979-05-27\nmixed = [1, \"two\", [3.5], \{a = 1\}]\nempty = []\n\"odd key\" = 1\n\n[server]\nhost = \"h\"\n\n[server.limits]\nmax = 5\n\n[[products]]\nname = \"a\"\n\n[[products]]\nname = \"b\"\n[products.tags]\nx = 1\n"
	parsed := (parse(text: source) | expect_ok?)
	text := (stringify(value: parsed) | expect_ok?)
	parse(text: text) | expect_ok? | expect_equal(parsed)?
	stringify(value: (parse(text: text) | expect_ok?)) | expect_ok? | expect_equal(text)?

test "TOML stringify requires a table root and honors max_bytes":
	wrong: String! := error(Error("invalid TOML input", kind: "EINVAL"))
	limited: String! := error(Error("TOML limit exceeded", kind: "EOVERFLOW"))
	stringify(value: TomlValue.IntValue(1)) | expect_equal(wrong)?

	root := (parse(text: "a = 1") | expect_ok?)
	stringify(value: root, max_bytes: 3) | expect_equal(limited)?

	exact: String! := ok("a = 1\n")
	stringify(value: root, max_bytes: 6) | expect_equal(exact)?
	stringify(value: root, max_bytes: -1) | expect_equal(wrong)?

fn repeated(text: String, count: Int) String:
	if count <= 0: return ""
	if count == 1: return text.clone()

	half := repeated(text: text.clone(), count: count / 2)
	if count % 2 == 1: return half.concat(half).concat(text)

	return half.concat(half)

test "TOML long strings parse and stringify in linear time":
	long := repeated(text: "x\\n", count: 150000)
	expected := repeated(text: "x\n", count: 150000)
	root := (parse(text: "a = \"{long}\"\nb = '''{expected}'''") | expect_ok?)
	table := (entries(root.clone())?)
	table["a"] | expect_equal(TomlValue.StringValue(expected.clone()))?
	table["b"] | expect_equal(TomlValue.StringValue(expected))?

	text := (stringify(value: root) | expect_ok?)
	parse(text: text) | expect_ok? | expect_equal(root)?

test "TOML stringify rejects invalid date-time text":
	invalid: String! := error(Error("invalid TOML input", kind: "EINVAL"))

	for text in ["bogus", "", "2024-13-01", "1979-05-27T07:32:00 junk"]:
		var table = Map[String, TomlValue]()
		table.add("x", TomlValue.DateTimeValue(text))
		expect_equal(stringify(TomlValue.TableValue(table.clone())), invalid)?

		var nested = Map[String, TomlValue]()
		nested.add("a", TomlValue.ArrayValue([TomlValue.TableValue(table)]))
		expect_equal(stringify(TomlValue.TableValue(nested)), invalid)?

	var good = Map[String, TomlValue]()
	good.add("x", TomlValue.DateTimeValue("1979-05-27T07:32:00Z"))
	expect_equal((stringify(TomlValue.TableValue(good))?), "x = 1979-05-27T07:32:00Z\n")?

test "TOML deeply nested inline tables parse in linear time":
	n := 6000
	text := "a = " + "\{ b = ".repeat(n).get() + "1" + " \}".repeat(n).get()
	started := monotonic()
	parsed := parse(text, TomlOptions())
	elapsed := monotonic().difference(started).to_milliseconds()
	value := parsed?
	expect_true(entries(value).is_ok())?
	if elapsed > 3000: return fail("nested inline tables took {elapsed} ms")

test "TOML parse without options stops deep nesting and none lifts it":
	deep := "a = " + "[".repeat(20000).get() + "]".repeat(20000).get()
	if parse(deep).is_ok(): return fail("nesting over the default depth was accepted")

	lifted := parse(deep, TomlOptions(max_depth: none, max_values: none))
	expect_true(lifted.is_ok())?
