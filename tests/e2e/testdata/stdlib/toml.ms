import {
    parse,
    stringify,
    TomlValue,
    TomlError,
    TomlLimits
} from "@std/toml.ms"
import {List, Map} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import Error from "@std/errors.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn entries(value: TomlValue) -> Map[String, TomlValue]:
    match value:
        TableValue(values): return values
        _: return panic("expected TOML table")

fn items(value: TomlValue) -> List[TomlValue]:
    match value:
        ArrayValue(values): return values
        _: return panic("expected TOML array")

fn limits(
    bytes: Optional[Int],
    depth: Optional[Int],
    values: Optional[Int]
) -> Optional[TomlLimits]:
    return some(TomlLimits(max_bytes: bytes, max_depth: depth, max_values: values))

test "TOML scalars quoted keys comments exact integers and dates":
    let source = "title = \"é🙂 # text\" # comment\n'' = 'literal\\n'\nbool = true\nlarge = 9007199254740993\nhex = 0xDEAD_BEEF\noct = 0o755\nbin = 0b1010\nfloat = -1_2.5e+2\ndate = 2024-02-29\ntime = 07:32:00.123\nstamp = 1979-05-27 07:32:00-07:00\n"
    let root = entries(value(parse(text: source)))
    if root.get("title").unwrap() != TomlValue.StringValue("é🙂 # text"): return panic(
        "TOML text"
    )
    if root.get("").unwrap() != TomlValue.StringValue("literal\\n"): return panic(
        "literal string"
    )
    if root.get("large").unwrap() != TomlValue.IntValue(9007199254740993): return panic(
        "exact integer"
    )
    if root.get("hex").unwrap() != TomlValue.IntValue(3735928559): return panic("hex")
    if root.get("oct").unwrap() != TomlValue.IntValue(493): return panic("octal")
    if root.get("bin").unwrap() != TomlValue.IntValue(10): return panic("binary")
    if root.get("float").unwrap() != TomlValue.FloatValue(-1250.0): return panic(
        "float"
    )
    if (
        root.get("stamp").unwrap() != TomlValue.DateTimeValue(
            "1979-05-27 07:32:00-07:00"
        )
    ): return panic("date time")
    if root.get("date").unwrap() != TomlValue.DateTimeValue("2024-02-29"): return panic(
        "date"
    )
    if root.get("time").unwrap() != TomlValue.DateTimeValue("07:32:00.123"): return panic(
        "time"
    )

test "TOML multiline strings Unicode escapes arrays and inline tables":
    let root = entries(
        value(
            parse(
                text: "basic = \"\"\"\nhello \\\n    world\\u0021\"\"\"\nliteral = '''\nraw\\text\nnext'''\narray = [1, # first\n true, \{name = 'Ada', meta.age = 37\},]\n"
            )
        )
    )
    if root.get("basic").unwrap() != TomlValue.StringValue("hello world!"): return panic(
        "multiline basic"
    )
    if root.get("literal").unwrap() != TomlValue.StringValue("raw\\text\nnext"): return panic(
        "multiline literal"
    )

    let array = items(root.get("array").unwrap())
    if array.length() != 3: return panic("array")

    let person = entries(array.at(2).unwrap())
    if person.get("name").unwrap() != TomlValue.StringValue("Ada"): return panic(
        "inline table"
    )
    if (
        entries(person.get("meta").unwrap()).get(
            "age"
        ).unwrap() != TomlValue.IntValue(37)
    ): return panic("inline dotted key")

test "TOML implicit parents dotted keys and arrays of tables":
    let text = "[owner.details]\nname = 'Ada'\n[owner]\nactive = true\n[[products]]\nname = 'Hammer'\n[products.meta]\nstock = 3\n[[products]]\nname = 'Nail'\n[[products.variants]]\nsize = 1\n[[products.variants]]\nsize = 2\n"
    let root = entries(value(parse(text: text)))
    let owner = entries(root.get("owner").unwrap())
    if (
        entries(owner.get("details").unwrap()).get(
            "name"
        ).unwrap() != TomlValue.StringValue("Ada")
    ): return panic("implicit parent")

    let products = items(root.get("products").unwrap())
    if products.length() != 2: return panic("table array")
    if (
        entries(entries(products.first().unwrap()).get("meta").unwrap()).get(
            "stock"
        ).unwrap() != TomlValue.IntValue(3)
    ): return panic("array child table")
    if items(entries(products.last().unwrap()).get("variants").unwrap()).length() != 2: return panic(
        "nested table arrays"
    )

    let dotted = entries(value(parse(text: "a.b.c = 1\na.b.d = 2\n")))
    if entries(entries(dotted.get("a").unwrap()).get("b").unwrap()).length() != 2: return panic(
        "dotted assignment"
    )

test "TOML rejects malformed data redefinitions and closed inline tables":
    for text in [
        "a=1\na=2",
        "[a]\n[a]",
        "a=1\n[a]",
        "a=\{b=1\}\na.c=2",
        "a.b=1\n[a]",
        "a=[1 2]",
        "a=[,]",
        "a=\{b=1,\}",
        "a=\{b=1\nb=2\}",
        "a=01",
        "a=1_",
        "a=_1",
        "a=1__2",
        "a=+0x1",
        "a=1.",
        "a=.1",
        "a=1e",
        "a=9223372036854775808",
        "a=2023-02-29",
        "a=24:00:00",
        "a='unterminated",
        "a=\"\\uD800\"",
        "a=\"\\q\"",
        "a=true false",
        "a=1\rb=2",
        "[a.b.c]\nz=9\n[a]\nb.c.t=1",
        "[[a.b]]\n[a]\nb.y=2"
    ]:
        let cause = match parse(text: text):
            ok(_): return panic("invalid TOML accepted: {text}")

            error(cause): cause

        match cause:
            InvalidData(line, column, reason):
                if (line < 1 or column < 1 or reason == ""): return panic(
                    "TOML error details"
                )

                let boundary = Error(cause)
                if not boundary.message().starts_with("TOML "): return panic(
                    "source Error implementation"
                )

            _: return panic("wrong TOML error")

test "TOML optional limits include implicit tables and zero":
    let limited: Result[TomlValue, TomlError] = error(TomlError.LimitExceeded)
    let invalid: Result[TomlValue, TomlError] = error(TomlError.InvalidInput)
    if (
        parse(
            text: "a=1",
            limits: limits(bytes: 2, depth: none, values: none)
        ) != limited
    ): return panic("byte limit")
    if (
        parse(
            text: "a.b=1",
            limits: limits(bytes: none, depth: 2, values: none)
        ) != limited
    ): return panic("depth limit")
    if (
        parse(
            text: "a.b=1",
            limits: limits(bytes: none, depth: none, values: 2)
        ) != limited
    ): return panic("value limit")
    if (
        parse(text: "", limits: limits(bytes: 0, depth: 1, values: 1)) != parse(
            text: ""
        )
    ): return panic("empty exact limits")
    if (parse(text: "", limits: limits(bytes: none, depth: none, values: 0)) != limited): return panic(
        "zero values"
    )
    if (
        parse(
            text: "",
            limits: limits(bytes: none, depth: -1, values: none)
        ) != invalid
    ): return panic("negative limit")
    if (
        parse(
            text: "a=1",
            limits: limits(bytes: 3, depth: 2, values: 2)
        ) != parse(text: "a=1")
    ): return panic("exact limits")

test "TOML nonfinite floats CRLF and repeated separators":
    let root = entries(
        value(
            parse(
                text: "positive=inf\r\nnegative=-inf\r\nnan=+nan\r\ninteger=1_000_000\r\n"
            )
        )
    )

    match root.get("positive").unwrap():
        FloatValue(number):
            if number.is_finite() or number < 0.0: return panic("positive infinity")

        _: return panic("expected float")

    match root.get("negative").unwrap():
        FloatValue(number):
            if number.is_finite() or number > 0.0: return panic("negative infinity")

        _: return panic("expected float")

    match root.get("nan").unwrap():
        FloatValue(number):
            if not number.is_nan(): return panic("NaN")

        _: return panic("expected float")

    if root.get("integer").unwrap() != TomlValue.IntValue(1000000): return panic(
        "repeated underscore separators"
    )

fn failure(text: String) -> String:
    match parse(text: text):
        ok(_): return "accepted"
        error(cause): return cause.message()

test "TOML errors report the offending line and column":
    if failure("x = 1\ny = \"a\u{1}b\"") != "TOML 2:7: invalid control character": return panic(
        "control character position"
    )
    if failure("x = 1\ny = 2\rz = 3") != "TOML 2:6: bare carriage return": return panic(
        "carriage return position"
    )
    if failure("x = 1\n\u{0}") != "TOML 2:1: invalid control character": return panic(
        "NUL position"
    )
    if failure("a = 1\u{0}") != "TOML 1:6: invalid control character": return panic(
        "trailing NUL position"
    )
    if failure("y = True") != "TOML 1:5: invalid value": return panic("True")
    if failure("y = yes") != "TOML 1:5: invalid value": return panic("yes")
    if failure("y = abc") != "TOML 1:5: invalid value": return panic("abc")
    if failure("x = 1\ny = 1e") != "TOML 2:5: invalid exponent": return panic(
        "exponent position"
    )

test "TOML limits fields default to none":
    let limited: Result[TomlValue, TomlError] = error(TomlError.LimitExceeded)
    if parse(text: "a=1", limits: some(TomlLimits(max_bytes: 2))) != limited: return panic(
        "partial byte limit"
    )
    if parse(text: "a=1", limits: some(TomlLimits())) != parse(text: "a=1"): return panic(
        "empty limits"
    )

test "TOML stringify round trips scalars tables and arrays of tables":
    let source = "title = \"é🙂 \\\"q\\\" \\t tab\\u0001\"\nint = -42\nfloat = 3.0\nbig = 1e+21\nflag = true\ndate = 1979-05-27\nmixed = [1, \"two\", [3.5], \{a = 1\}]\nempty = []\n\"odd key\" = 1\n\n[server]\nhost = \"h\"\n\n[server.limits]\nmax = 5\n\n[[products]]\nname = \"a\"\n\n[[products]]\nname = \"b\"\n[products.tags]\nx = 1\n"
    let parsed = value(parse(text: source))
    let text = value(stringify(value: parsed))
    if value(parse(text: text)) != parsed: return panic("TOML stringify round trip")
    if value(stringify(value: value(parse(text: text)))) != text: return panic(
        "TOML stringify is stable"
    )

test "TOML stringify requires a table root and honors max_bytes":
    let wrong: Result[String, TomlError] = error(TomlError.InvalidInput)
    let limited: Result[String, TomlError] = error(TomlError.LimitExceeded)
    if stringify(value: TomlValue.IntValue(1)) != wrong: return panic("non-table root")

    let root = value(parse(text: "a = 1"))
    if stringify(value: root, max_bytes: 3) != limited: return panic("output limit")

    let exact: Result[String, TomlError] = ok("a = 1\n")
    if stringify(value: root, max_bytes: 6) != exact: return panic("exact limit")
    if stringify(value: root, max_bytes: -1) != wrong: return panic("negative limit")

fn repeated(text: String, count: Int) -> String:
    if count <= 0: return ""
    if count == 1: return text

    let half = repeated(text: text, count: count / 2)
    if count % 2 == 1: return half.concat(half).concat(text)

    return half.concat(half)

test "TOML long strings parse and stringify in linear time":
    let long = repeated(text: "x\\n", count: 150000)
    let expected = repeated(text: "x\n", count: 150000)
    let root = value(parse(text: "a = \"{long}\"\nb = '''{expected}'''"))
    let table = entries(root)
    if table.get("a").unwrap() != TomlValue.StringValue(expected): return panic(
        "basic string"
    )
    if table.get("b").unwrap() != TomlValue.StringValue(expected): return panic(
        "literal multi-line string"
    )

    let text = value(stringify(value: root))
    if value(parse(text: text)) != root: return panic("long string round trip")
