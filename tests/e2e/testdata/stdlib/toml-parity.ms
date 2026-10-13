import {
    parse,
    stringify,
    TomlValue,
    TomlError,
    TomlLimits
} from "@std/toml.ms"
import {List, Map} from "@std/collections.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn entries(value: TomlValue) -> Map[String, TomlValue]:
    match value:
        TableValue(values): return values
        _: return panic("expected TOML table")

fn invalid(value: TomlValue) -> Unit:
    let cause = match stringify(value):
        ok(_): return panic("invalid TOML value accepted")
        error(cause): cause

    match cause:
        InvalidData(line, column, reason):
            if (
                line != 0
                or column != 0
                or reason == ""
            ): return panic("TOML serialization diagnostic")
        _: return panic("wrong TOML serialization error")

test "TOML stringify preserves Unicode nested values exact integers and date text":
    let fields = Map[String, TomlValue]()
    fields.add(
        key: "",
        value: TomlValue.StringValue("é🙂\n\r\t\u{0}\u{1}\u{8}\u{c}\u{7f}\\\"")
    )
    fields.add(
        key: "quoted\".key\n",
        value: TomlValue.StringValue("true # literal")
    )
    fields.add(
        key: "numbers",
        value: TomlValue.ArrayValue(
            [
                TomlValue.IntValue((-9223372036854775808)),
                TomlValue.IntValue(9223372036854775807),
                TomlValue.IntValue(9007199254740993),
                TomlValue.FloatValue(1.0),
                TomlValue.FloatValue(1.25e-9)
            ]
        )
    )
    fields.add(
        key: "calendar",
        value: TomlValue.ArrayValue(
            [
                TomlValue.DateTimeValue("2024-02-29"),
                TomlValue.DateTimeValue("07:32:00.123"),
                TomlValue.DateTimeValue("1979-05-27 07:32:00-07:00")
            ]
        )
    )
    let nested = Map[String, TomlValue]()
    nested.add(
        key: "enabled",
        value: TomlValue.BoolValue(true)
    )
    nested.add(
        key: "array",
        value: TomlValue.ArrayValue([])
    )
    nested.add(
        key: "empty",
        value: TomlValue.TableValue(Map[String, TomlValue]())
    )
    fields.add(
        key: "nested",
        value: TomlValue.TableValue(nested)
    )
    let tree = TomlValue.TableValue(fields)
    let encoded = value(stringify(tree))
    if value(parse(encoded)) != tree: return panic("TOML value/kind round trip")
    if not encoded.contains("1.0"): return panic("integral Float became Int")
    if fields.get("quoted\".key\n").unwrap() != TomlValue.StringValue("true # literal"): return panic(
        "TOML input mutated"
    )

test "TOML stringify preserves signed zero and nonfinite float kinds":
    let original = value(
        parse("zero = -0.0\npositive = inf\nnegative = -inf\nnan = nan\n")
    )
    let encoded = value(stringify(original))
    let decoded = entries(
        value(parse(encoded))
    )
    if not encoded.contains("-0.0"): return panic("negative zero formatting")

    match decoded.get("zero").unwrap():
        FloatValue(number):
            if number.to_string() != "-0": return panic("negative zero changed")
        _: return panic("zero kind changed")

    match decoded.get("positive").unwrap():
        FloatValue(number):
            if number.is_finite() or number < 0.0: return panic(
                "positive infinity changed"
            )
        _: return panic("positive infinity kind changed")

    match decoded.get("negative").unwrap():
        FloatValue(number):
            if number.is_finite() or number > 0.0: return panic(
                "negative infinity changed"
            )
        _: return panic("negative infinity kind changed")

    match decoded.get("nan").unwrap():
        FloatValue(number):
            if not number.is_nan(): return panic("NaN changed")
        _: return panic("NaN kind changed")

test "TOML stringify rejects invalid roots dates and NaN-bearing cyclic graphs":
    invalid(TomlValue.IntValue(1))
    invalid(TomlValue.ArrayValue([]))

    for token in [
        "",
        "2023-02-29",
        "24:00:00",
        "2024-02-29\nx = 1",
        "2024-02-29T00:00:00+24:00"
    ]:
        let fields = Map[String, TomlValue]()
        fields.add(
            key: "date",
            value: TomlValue.DateTimeValue(token)
        )
        invalid(TomlValue.TableValue(fields))

    let nan = entries(
        value(parse("value = nan"))
    ).get("value").unwrap()
    let items: List[TomlValue] = [nan]
    let array_cycle = TomlValue.ArrayValue(items)
    items.append(array_cycle)
    let root = Map[String, TomlValue]()
    root.add(key: "array", value: array_cycle)
    invalid(TomlValue.TableValue(root))
    if items.length() != 2: return panic("TOML cycle detection mutated input")

    let fields = Map[String, TomlValue]()
    let table_cycle = TomlValue.TableValue(fields)
    fields.add(key: "nan", value: nan)
    fields.add(key: "self", value: table_cycle)
    invalid(table_cycle)
    if fields.length() != 2: return panic("TOML table detection mutated input")

test "TOML stringify emits shared subtrees at every occurrence":
    let fields = Map[String, TomlValue]()
    let nested = Map[String, TomlValue]()
    nested.add(
        key: "number",
        value: TomlValue.IntValue(7)
    )
    let shared = TomlValue.TableValue(nested)
    let array = TomlValue.ArrayValue([shared, shared])
    fields.add(key: "first", value: array)
    fields.add(key: "second", value: array)
    let tree = TomlValue.TableValue(fields)
    if value(
        parse(
            value(stringify(tree))
        )
    ) != tree: return panic("TOML shared subtree rejected")

    nested.add(
        key: "number",
        value: TomlValue.IntValue(8)
    )
    if not value(stringify(tree)).contains("8"): return panic(
        "TOML shared storage detached"
    )

test "TOML stringify honors exact output root depth and value budgets":
    let root = Map[String, TomlValue]()
    root.add(
        key: "a",
        value: TomlValue.IntValue(1)
    )
    let tree = TomlValue.TableValue(root)
    let limited: Result[String, TomlError] = error(TomlError.LimitExceeded)
    let invalid: Result[String, TomlError] = error(TomlError.InvalidInput)
    if (
        value(
            stringify(
                tree,
                TomlLimits(max_bytes: 8, max_depth: 2, max_values: 2)
            )
        ) != "\"a\" = 1\n"
    ): return panic("TOML exact budgets")
    if (
        stringify(
            tree,
            TomlLimits(max_bytes: 7, max_depth: none, max_values: none)
        ) != limited
    ): return panic("TOML output byte budget")
    if (
        stringify(
            tree,
            TomlLimits(max_bytes: none, max_depth: 1, max_values: none)
        ) != limited
    ): return panic("TOML depth budget")
    if (
        stringify(
            tree,
            TomlLimits(max_bytes: none, max_depth: none, max_values: 1)
        ) != limited
    ): return panic("TOML count budget")
    if (
        stringify(
            tree,
            TomlLimits(max_bytes: none, max_depth: none, max_values: -1)
        ) != invalid
    ): return panic("TOML negative budget")

    let empty = TomlValue.TableValue(Map[String, TomlValue]())
    if (
        value(
            stringify(
                empty,
                TomlLimits(max_bytes: 0, max_depth: 1, max_values: 1)
            )
        ) != ""
    ): return panic("TOML empty document budgets")
    if (
        stringify(
            empty,
            TomlLimits(max_bytes: 0, max_depth: 0, max_values: 1)
        ) != limited
    ): return panic("TOML zero depth budget")
    if (
        stringify(
            empty,
            TomlLimits(max_bytes: 0, max_depth: 1, max_values: 0)
        ) != limited
    ): return panic("TOML zero count budget")

    let utf8 = Map[String, TomlValue]()
    utf8.add(
        key: "é",
        value: TomlValue.StringValue("🙂")
    )
    let unicode_tree = TomlValue.TableValue(utf8)
    let encoded = value(stringify(unicode_tree))
    if (
        value(
            stringify(
                unicode_tree,
                TomlLimits(
                    max_bytes: encoded.byte_length(),
                    max_depth: none,
                    max_values: none
                )
            )
        ) != encoded
    ): return panic("TOML exact UTF-8 budget")
    if (
        stringify(
            unicode_tree,
            TomlLimits(
                max_bytes: encoded.byte_length() - 1,
                max_depth: none,
                max_values: none
            )
        ) != limited
    ): return panic("TOML short UTF-8 budget")
