import {parse, stringify, TomlValue, TomlError, TomlLimits} from "@std/toml.ms"
import panic from "@std/faults.ms"

fn entries(value: TomlValue) Map[String, TomlValue]:
    match value:
        TableValue(values): return values
        _: return panic("expected TOML table")

fn items(value: TomlValue) List[TomlValue]:
    match value:
        ArrayValue(values): return values
        _: return panic("expected TOML array")

fn limits(
    bytes: Optional[Int],
    depth: Optional[Int],
    values: Optional[Int]
) Optional[TomlLimits]:
    return some(TomlLimits(bytes, depth, values))

test "TOML scalars quoted keys comments exact integers and dates":
    let source = "title = \"é🙂 # text\" # comment\n'' = 'literal\\n'\nbool = true\nlarge = 9007199254740993\nhex = 0xDEAD_BEEF\noct = 0o755\nbin = 0b1010\nfloat = -1_2.5e+2\ndate = 2024-02-29\ntime = 07:32:00.123\nstamp = 1979-05-27 07:32:00-07:00\n"
    let root = parse(source) | try | entries
    if root.get("title").get() != TomlValue.StringValue("é🙂 # text"): return panic(
        "TOML text"
    )
    if root.get("").get() != TomlValue.StringValue("literal\\n"): return panic(
        "literal string"
    )
    if root.get("large").get() != TomlValue.IntValue(9007199254740993): return panic(
        "exact integer"
    )
    if root.get("hex").get() != TomlValue.IntValue(3735928559): return panic("hex")
    if root.get("oct").get() != TomlValue.IntValue(493): return panic("octal")
    if root.get("bin").get() != TomlValue.IntValue(10): return panic("binary")
    if root.get("float").get() != TomlValue.FloatValue(-1250.0): return panic("float")
    if (root.get("stamp").get() != TomlValue.DateTimeValue("1979-05-27 07:32:00-07:00")): return panic(
        "date time"
    )
    if root.get("date").get() != TomlValue.DateTimeValue("2024-02-29"): return panic(
        "date"
    )
    if root.get("time").get() != TomlValue.DateTimeValue("07:32:00.123"): return panic(
        "time"
    )

test "TOML multiline strings Unicode escapes arrays and inline tables":
    let root = parse(
        "basic = \"\"\"\nhello \\\n    world\\u0021\"\"\"\nliteral = '''\nraw\\text\nnext'''\narray = [1, # first\n true, \{name = 'Ada', meta.age = 37\},]\n"
    ) | try | entries
    if root.get("basic").get() != TomlValue.StringValue("hello world!"): return panic(
        "multiline basic"
    )
    if root.get("literal").get() != TomlValue.StringValue("raw\\text\nnext"): return panic(
        "multiline literal"
    )

    let array = items(root.get("array").get())
    if array.length() != 3: return panic("array")

    let person = entries(array.at(2).get())
    if person.get("name").get() != TomlValue.StringValue("Ada"): return panic(
        "inline table"
    )
    if (entries(person.get("meta").get()).get("age").get() != TomlValue.IntValue(37)): return panic(
        "inline dotted key"
    )

test "TOML implicit parents dotted keys and arrays of tables":
    let text = "[owner.details]\nname = 'Ada'\n[owner]\nactive = true\n[[products]]\nname = 'Hammer'\n[products.meta]\nstock = 3\n[[products]]\nname = 'Nail'\n[[products.variants]]\nsize = 1\n[[products.variants]]\nsize = 2\n"
    let root = parse(text) | try | entries
    let owner = entries(root.get("owner").get())
    if (
        entries(owner.get("details").get()).get(
            "name"
        ).get() != TomlValue.StringValue("Ada")
    ): return panic("implicit parent")

    let products = items(root.get("products").get())
    if products.length() != 2: return panic("table array")
    if (
        entries(entries(products.first().get()).get("meta").get()).get(
            "stock"
        ).get() != TomlValue.IntValue(3)
    ): return panic("array child table")
    if items(entries(products.last().get()).get("variants").get()).length() != 2: return panic(
        "nested table arrays"
    )

    let dotted = parse("a.b.c = 1\na.b.d = 2\n") | try | entries
    if entries(entries(dotted.get("a").get()).get("b").get()).length() != 2: return panic(
        "dotted assignment"
    )

test "TOML rejects malformed data redefinitions and closed inline tables":
    for text in [
        "a=1\na=2", "[a]\n[a]", "a=1\n[a]", "a=\{b=1\}\na.c=2", "a.b=1\n[a]", "a=[1 2]",
        "a=[,]", "a=\{b=1,\}", "a=\{b=1\nb=2\}", "a=01", "a=1_", "a=_1", "a=1__2",
        "a=+0x1", "a=1.", "a=.1", "a=1e", "a=9223372036854775808", "a=2023-02-29",
        "a=24:00:00", "a='unterminated", "a=\"\\uD800\"", "a=\"\\q\"", "a=true false",
        "a=1\rb=2", "[a.b.c]\nz=9\n[a]\nb.c.t=1", "[[a.b]]\n[a]\nb.y=2"
    ]:
        let parsed = parse(text)
        if parsed.is_ok(): return panic("invalid TOML accepted: {text}")

        let cause = parsed.err()

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
    if (parse("a=1", limits(2, none, none)) != limited): return panic("byte limit")
    if (parse("a.b=1", limits(none, 2, none)) != limited): return panic("depth limit")
    if (parse("a.b=1", limits(none, none, 2)) != limited): return panic("value limit")
    if (parse("", limits(0, 1, 1)) != parse("")): return panic("empty exact limits")
    if (parse("", limits(none, none, 0)) != limited): return panic("zero values")
    if (parse("", limits(none, -1, none)) != invalid): return panic("negative limit")
    if (parse("a=1", limits(3, 2, 2)) != parse("a=1")): return panic("exact limits")

test "TOML nonfinite floats CRLF and repeated separators":
    let root = parse(
        "positive=inf\r\nnegative=-inf\r\nnan=+nan\r\ninteger=1_000_000\r\n"
    ) | try | entries

    match root.get("positive").get():
        FloatValue(number):
            if number.is_finite() or number < 0.0: return panic("positive infinity")
        _: return panic("expected float")

    match root.get("negative").get():
        FloatValue(number):
            if number.is_finite() or number > 0.0: return panic("negative infinity")
        _: return panic("expected float")

    match root.get("nan").get():
        FloatValue(number):
            if not number.is_nan(): return panic("NaN")
        _: return panic("expected float")

    if root.get("integer").get() != TomlValue.IntValue(1000000): return panic(
        "repeated underscore separators"
    )

fn failure(text: String) String:
    let parsed = parse(text)
    if parsed.is_ok(): return "accepted"

    return parsed.err().message()

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
    if parse("a=1", some(TomlLimits(2))) != limited: return panic("partial byte limit")
    if parse("a=1", some(TomlLimits())) != parse("a=1"): return panic("empty limits")

test "TOML stringify round trips scalars tables and arrays of tables":
    let source = "title = \"é🙂 \\\"q\\\" \\t tab\\u0001\"\nint = -42\nfloat = 3.0\nbig = 1e+21\nflag = true\ndate = 1979-05-27\nmixed = [1, \"two\", [3.5], \{a = 1\}]\nempty = []\n\"odd key\" = 1\n\n[server]\nhost = \"h\"\n\n[server.limits]\nmax = 5\n\n[[products]]\nname = \"a\"\n\n[[products]]\nname = \"b\"\n[products.tags]\nx = 1\n"
    let parsed = try parse(source)
    let text = try stringify(parsed)
    if (try parse(text)) != parsed: return panic("TOML stringify round trip")
    if (parse(text) | try | stringify | try) != text: return panic(
        "TOML stringify is stable"
    )

test "TOML stringify requires a table root and honors max_bytes":
    let wrong: Result[String, TomlError] = error(TomlError.InvalidInput)
    let limited: Result[String, TomlError] = error(TomlError.LimitExceeded)
    if stringify(TomlValue.IntValue(1)) != wrong: return panic("non-table root")

    let root = try parse("a = 1")
    if stringify(root, 3) != limited: return panic("output limit")

    let exact: Result[String, TomlError] = ok("a = 1\n")
    if stringify(root, 6) != exact: return panic("exact limit")
    if stringify(root, -1) != wrong: return panic("negative limit")

fn repeated(text: String, count: Int) String:
    if count <= 0: return ""
    if count == 1: return text

    let half = repeated(text, count / 2)
    if count % 2 == 1: return half.concat(half).concat(text)

    return half.concat(half)

test "TOML long strings parse and stringify in linear time":
    let long = repeated("x\\n", 150000)
    let expected = repeated("x\n", 150000)
    let root = try parse("a = \"{long}\"\nb = '''{expected}'''")
    let table = entries(root)
    if table.get("a").get() != TomlValue.StringValue(expected): return panic(
        "basic string"
    )
    if table.get("b").get() != TomlValue.StringValue(expected): return panic(
        "literal multi-line string"
    )

    let text = try stringify(root)
    if (try parse(text)) != root: return panic("long string round trip")

test "TOML stringify rejects invalid date-time text":
    let invalid: Result[String, TomlError] = error(TomlError.InvalidInput)

    for text in ["bogus", "", "2024-13-01", "1979-05-27T07:32:00 junk"]:
        let table = Map[String, TomlValue]().add("x", TomlValue.DateTimeValue(text))
        if stringify(TomlValue.TableValue(table)) != invalid: return panic(
            "invalid date-time text"
        )

        let nested = Map[String, TomlValue]().add(
            "a",
            TomlValue.ArrayValue([TomlValue.TableValue(table)])
        )
        if stringify(TomlValue.TableValue(nested)) != invalid: return panic(
            "nested invalid date-time text"
        )

    let good = Map[String, TomlValue]().add(
        "x",
        TomlValue.DateTimeValue("1979-05-27T07:32:00Z")
    )
    if ((try stringify(TomlValue.TableValue(good))) != "x = 1979-05-27T07:32:00Z\n"): return panic(
        "valid date-time text"
    )
