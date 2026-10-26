from "@std/test.ms" import expect_equal, expect_false, expect_ok, expect_true, fail
from "@std/core.ms" import TextError
from "@std/toml.ms" import parse, stringify, TomlValue, TomlError, TomlLimits
from "@std/time.ms" import clock

def entries(value: TomlValue) -> Result[Map[String, TomlValue], Error]:
    match value:
        case TableValue(values): return ok(values)
        case _: return error(TextError("expected TOML table"))

def items(value: TomlValue) -> Result[List[TomlValue], Error]:
    match value:
        case ArrayValue(values): return ok(values)
        case _: return error(TextError("expected TOML array"))

def limits(
    bytes: Optional[Int],
    depth: Optional[Int],
    values: Optional[Int]
) -> Optional[TomlLimits]:
    return some(TomlLimits(max_bytes: bytes, max_depth: depth, max_values: values))

test "TOML scalars quoted keys comments exact integers and dates":
    let source = "title = \"é🙂 # text\" # comment\n'' = 'literal\\n'\nbool = true\nlarge = 9007199254740993\nhex = 0xDEAD_BEEF\noct = 0o755\nbin = 0b1010\nfloat = -1_2.5e+2\ndate = 2024-02-29\ntime = 07:32:00.123\nstamp = 1979-05-27 07:32:00-07:00\n"
    let root = parse(text: source) | try expect_ok | try entries
    (root.get("title").get() | try expect_equal(TomlValue.StringValue("é🙂 # text")))
    root.get("").get() | try expect_equal(TomlValue.StringValue("literal\\n"))
    root.get("large").get() | try expect_equal(TomlValue.IntValue(9007199254740993))
    root.get("hex").get() | try expect_equal(TomlValue.IntValue(3735928559))
    root.get("oct").get() | try expect_equal(TomlValue.IntValue(493))
    root.get("bin").get() | try expect_equal(TomlValue.IntValue(10))
    root.get("float").get() | try expect_equal(TomlValue.FloatValue(-1250.0))
    try expect_false(
        (
            root.get("stamp").get() != TomlValue.DateTimeValue(
                "1979-05-27 07:32:00-07:00"
            )
        )
    )
    root.get("date").get() | try expect_equal(TomlValue.DateTimeValue("2024-02-29"))
    root.get("time").get() | try expect_equal(TomlValue.DateTimeValue("07:32:00.123"))

test "TOML multiline strings Unicode escapes arrays and inline tables":
    let root = (
        try entries(
            (
                parse(
                    text: "basic = \"\"\"\nhello \\\n    world\\u0021\"\"\"\nliteral = '''\nraw\\text\nnext'''\narray = [1, # first\n true, {name = 'Ada', meta.age = 37},]\n"
                ) | try expect_ok
            )
        )
    )
    root.get("basic").get() | try expect_equal(TomlValue.StringValue("hello world!"))
    root.get("literal").get() | try expect_equal(
        TomlValue.StringValue("raw\\text\nnext")
    )

    let array = (try items(root.get("array").get()))
    array.length() | try expect_equal(3)

    let person = (try entries(array.get(2).clone()))
    person.get("name").get() | try expect_equal(TomlValue.StringValue("Ada"))
    try expect_false(
        (
            (try entries(person.get("meta").get())).get(
                "age"
            ).get() != TomlValue.IntValue(37)
        )
    )

test "TOML implicit parents dotted keys and arrays of tables":
    let text = "[owner.details]\nname = 'Ada'\n[owner]\nactive = true\n[[products]]\nname = 'Hammer'\n[products.meta]\nstock = 3\n[[products]]\nname = 'Nail'\n[[products.variants]]\nsize = 1\n[[products.variants]]\nsize = 2\n"
    let root = parse(text: text) | try expect_ok | try entries
    let owner = (try entries(root.get("owner").get()))
    try expect_false(
        (
            (try entries(owner.get("details").get())).get(
                "name"
            ).get() != TomlValue.StringValue("Ada")
        )
    )

    let products = (try items(root.get("products").get()))
    products.length() | try expect_equal(2)
    try expect_false(
        (
            (
                try entries(
                    (try entries(products.first().get())).get(
                        "meta"
                    ).get()
                )
            ).get("stock").get() != TomlValue.IntValue(3)
        )
    )
    (try items((try entries(products.last().get())).get("variants").get())).length() | try expect_equal(
        2
    )

    let dotted = parse(text: "a.b.c = 1\na.b.d = 2\n") | try expect_ok | try entries
    (try entries((try entries(dotted.get("a").get())).get("b").get())).length() | try expect_equal(
        2
    )

test "TOML rejects malformed data redefinitions and closed inline tables":
    for text in [
        "a=1\na=2", "[a]\n[a]", "a=1\n[a]", "a={b=1}\na.c=2", "a.b=1\n[a]", "a=[1 2]",
        "a=[,]", "a={b=1,}", "a={b=1\nb=2}", "a=01", "a=1_", "a=_1", "a=1__2", "a=+0x1",
        "a=1.", "a=.1", "a=1e", "a=9223372036854775808", "a=2023-02-29", "a=24:00:00",
        "a='unterminated", "a=\"\\uD800\"", "a=\"\\q\"", "a=true false", "a=1\rb=2",
        "[a.b.c]\nz=9\n[a]\nb.c.t=1", "[[a.b]]\n[a]\nb.y=2"
    ]:
        let cause = match parse(text: text):
            case ok(_): return fail(f"invalid TOML accepted: {text}")
            case error(cause): cause

        match cause:
            case InvalidData(line, column, reason):
                (line < 1 or column < 1 or reason == "") | try expect_false

                let boundary: Error = cause
                ((boundary.message().starts_with("TOML ")) | try expect_true)
            case _: return fail("wrong TOML error")

test "TOML optional limits include implicit tables and zero":
    let limited: Result[TomlValue, TomlError] = error(TomlError.LimitExceeded)
    let invalid: Result[TomlValue, TomlError] = error(TomlError.InvalidInput)
    try expect_false(
        (
            parse(
                text: "a=1", limits: limits(bytes: 2, depth: none, values: none)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "a.b=1", limits: limits(bytes: none, depth: 2, values: none)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "a.b=1", limits: limits(bytes: none, depth: none, values: 2)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "", limits: limits(bytes: 0, depth: 1, values: 1)
            ) != parse(text: "")
        )
    )
    parse(text: "", limits: limits(bytes: none, depth: none, values: 0)) | try expect_equal(
        limited
    )
    try expect_false(
        (
            parse(
                text: "", limits: limits(bytes: none, depth: -1, values: none)
            ) != invalid
        )
    )
    try expect_false(
        (
            parse(
                text: "a=1", limits: limits(bytes: 3, depth: 2, values: 2)
            ) != parse(text: "a=1")
        )
    )

test "TOML nonfinite floats CRLF and repeated separators":
    let root = (
        try entries(
            (
                parse(
                    text: "positive=inf\r\nnegative=-inf\r\nnan=+nan\r\ninteger=1_000_000\r\n"
                ) | try expect_ok
            )
        )
    )

    match root.get("positive").get():
        case FloatValue(number):
            ((number.is_finite() or number < 0.0) | try expect_false)
        case _: return fail("expected float")

    match root.get("negative").get():
        case FloatValue(number):
            ((number.is_finite() or number > 0.0) | try expect_false)
        case _: return fail("expected float")

    match root.get("nan").get():
        case FloatValue(number):
            ((number.is_nan()) | try expect_true)
        case _: return fail("expected float")

    root.get("integer").get() | try expect_equal(TomlValue.IntValue(1000000))

def failure(text: String) -> String:
    match parse(text: text):
        case ok(_): return "accepted"
        case error(cause): return cause.message()

test "TOML errors report the offending line and column":
    failure(f"x = 1\ny = \"a\u{1}b\"") | try expect_equal(
        "TOML 2:7: invalid control character"
    )
    failure("x = 1\ny = 2\rz = 3") | try expect_equal("TOML 2:6: bare carriage return")
    failure(f"x = 1\n\u{0}") | try expect_equal("TOML 2:1: invalid control character")
    failure(f"a = 1\u{0}") | try expect_equal("TOML 1:6: invalid control character")
    failure("y = True") | try expect_equal("TOML 1:5: invalid value")
    failure("y = yes") | try expect_equal("TOML 1:5: invalid value")
    failure("y = abc") | try expect_equal("TOML 1:5: invalid value")
    failure("x = 1\ny = 1e") | try expect_equal("TOML 2:5: invalid exponent")

test "TOML limits fields default to none":
    let limited: Result[TomlValue, TomlError] = error(TomlError.LimitExceeded)
    parse(text: "a=1", limits: some(TomlLimits(max_bytes: 2))) | try expect_equal(
        limited
    )
    parse(text: "a=1", limits: some(TomlLimits())) | try expect_equal(
        parse(text: "a=1")
    )

test "TOML stringify round trips scalars tables and arrays of tables":
    let source = "title = \"é🙂 \\\"q\\\" \\t tab\\u0001\"\nint = -42\nfloat = 3.0\nbig = 1e+21\nflag = true\ndate = 1979-05-27\nmixed = [1, \"two\", [3.5], {a = 1}]\nempty = []\n\"odd key\" = 1\n\n[server]\nhost = \"h\"\n\n[server.limits]\nmax = 5\n\n[[products]]\nname = \"a\"\n\n[[products]]\nname = \"b\"\n[products.tags]\nx = 1\n"
    let parsed = (parse(text: source) | try expect_ok)
    let text = (stringify(value: parsed) | try expect_ok)
    parse(text: text) | try expect_ok | try expect_equal(parsed)
    stringify(value: (parse(text: text) | try expect_ok)) | try expect_ok | try expect_equal(
        text
    )

test "TOML stringify requires a table root and honors max_bytes":
    let wrong: Result[String, TomlError] = error(TomlError.InvalidInput)
    let limited: Result[String, TomlError] = error(TomlError.LimitExceeded)
    stringify(value: TomlValue.IntValue(1)) | try expect_equal(wrong)

    let root = (parse(text: "a = 1") | try expect_ok)
    stringify(value: root, max_bytes: 3) | try expect_equal(limited)

    let exact: Result[String, TomlError] = ok("a = 1\n")
    stringify(value: root, max_bytes: 6) | try expect_equal(exact)
    stringify(value: root, max_bytes: -1) | try expect_equal(wrong)

def repeated(text: String, count: Int) -> String:
    if count <= 0: return ""
    if count == 1: return text

    let half = repeated(text: text.clone(), count: count / 2)
    if count % 2 == 1: return half.concat(half).concat(text)

    return half.concat(half)

test "TOML long strings parse and stringify in linear time":
    let long = repeated(text: "x\\n", count: 150000)
    let expected = repeated(text: "x\n", count: 150000)
    let root = (parse(text: f"a = \"{long}\"\nb = '''{expected}'''") | try expect_ok)
    let table = (try entries(root.clone()))
    table.get("a").get() | try expect_equal(TomlValue.StringValue(expected.clone()))
    table.get("b").get() | try expect_equal(TomlValue.StringValue(expected))

    let text = (stringify(value: root) | try expect_ok)
    parse(text: text) | try expect_ok | try expect_equal(root)

test "TOML stringify rejects invalid date-time text":
    let invalid: Result[String, TomlError] = error(TomlError.InvalidInput)

    for text in ["bogus", "", "2024-13-01", "1979-05-27T07:32:00 junk"]:
        var table = Map[String, TomlValue]()
        table.add("x", TomlValue.DateTimeValue(text))
        try expect_equal(stringify(TomlValue.TableValue(table.clone())), invalid)

        var nested = Map[String, TomlValue]()
        nested.add("a", TomlValue.ArrayValue([TomlValue.TableValue(table)]))
        try expect_equal(stringify(TomlValue.TableValue(nested)), invalid)

    var good = Map[String, TomlValue]()
    good.add("x", TomlValue.DateTimeValue("1979-05-27T07:32:00Z"))
    try expect_equal(
        (try stringify(TomlValue.TableValue(good))), "x = 1979-05-27T07:32:00Z\n"
    )

test "TOML deeply nested inline tables parse in linear time":
    let n = 6000
    let text = "a = " + "{ b = ".repeat(n).get() + "1" + " }".repeat(n).get()
    let started = clock().now()
    let parsed = parse(text, some(TomlLimits()))
    let elapsed = clock().now().difference(started).to_milliseconds()
    let value = try parsed
    try expect_true(entries(value).is_ok())
    if elapsed > 3000: return fail(f"nested inline tables took {elapsed} ms")

test "TOML parse without limits stops deep nesting and an empty limits record lifts it":
    let deep = "a = " + "[".repeat(20000).get() + "]".repeat(20000).get()
    if parse(deep).is_ok(): return fail("nesting over the default depth was accepted")

    let lifted = parse(deep, some(TomlLimits()))
    try expect_true(lifted.is_ok())
