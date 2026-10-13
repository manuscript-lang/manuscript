import {
    parse,
    stringify,
    YamlValue,
    YamlError,
    YamlLimits
} from "@std/yaml.ms"
import {List, Map} from "@std/collections.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "YAML stringify preserves kinds number text quoting and Unicode":
    let fields = Map[String, YamlValue]()
    fields.add(
        key: "<<",
        value: YamlValue.StringValue("literal merge key")
    )
    fields.add(
        key: "",
        value: YamlValue.StringValue("null")
    )
    fields.add(
        key: "quote\"\\\n",
        value: YamlValue.StringValue("é🙂\n\r\t\u{0}\u{1}\u{85}\u{2028}\u{2029}")
    )
    fields.add(
        key: "numbers",
        value: YamlValue.ArrayValue(
            [
                YamlValue.NumberValue("9007199254740993"),
                YamlValue.NumberValue("0xFF"),
                YamlValue.NumberValue("+1.25e-9"),
                YamlValue.NumberValue("-.inf"),
                YamlValue.NumberValue(".NaN")
            ]
        )
    )
    fields.add(
        key: "other",
        value: YamlValue.ArrayValue(
            [
                YamlValue.Null,
                YamlValue.BoolValue(true),
                YamlValue.BoolValue(false),
                YamlValue.StringValue("true"),
                YamlValue.ArrayValue([]),
                YamlValue.ObjectValue(Map[String, YamlValue]())
            ]
        )
    )
    let tree = YamlValue.ObjectValue(fields)
    let encoded = value(stringify(tree))
    if value(parse(encoded)) != tree: return panic("YAML kind/text round trip")
    if fields.get("<<").unwrap() != YamlValue.StringValue("literal merge key"): return panic(
        "YAML input mutated"
    )
    if (
        value(parse("'<<': 42")) != YamlValue.ObjectValue(
            Map[String, YamlValue]().add(
                key: "<<",
                value: YamlValue.NumberValue("42")
            )
        )
    ): return panic("quoted block merge key")

test "YAML stringify rejects malformed numbers and cyclic values":
    for number in ["", "true", "1 2", "NaN", "1_000", "0xGG", "1e", "-0xFF"]:
        let cause = match stringify(YamlValue.NumberValue(number)):
            ok(_): return panic("invalid YAML number accepted")
            error(cause): cause

        match cause:
            InvalidData(line, column, reason):
                if (
                    line != 0
                    or column != 0
                    or reason == ""
                ): return panic("YAML serialization diagnostic")
            _: return panic("wrong YAML error")

    let values: List[YamlValue] = []
    let cycle = YamlValue.ArrayValue(values)
    values.append(cycle)

    let cause = match stringify(cycle):
        ok(_): return panic("YAML cycle accepted")
        error(cause): cause

    match cause:
        InvalidData(_, _, reason):
            if reason != "cyclic YAML value": return panic("YAML cycle reason")
        _: return panic("YAML cycle error")

    let fields = Map[String, YamlValue]()
    let object_cycle = YamlValue.ObjectValue(fields)
    fields.add(
        key: "number",
        value: YamlValue.NumberValue(".nan")
    )
    fields.add(key: "self", value: object_cycle)

    let object_error = match stringify(object_cycle):
        ok(_): return panic("YAML map cycle accepted")
        error(cause): cause

    match object_error:
        InvalidData(_, _, _): let ignored = unit
        _: return panic("YAML map cycle error")

    let shared = YamlValue.ArrayValue([YamlValue.StringValue("shared")])
    let tree = YamlValue.ArrayValue([shared, shared])
    if value(
        parse(
            value(stringify(tree))
        )
    ) != tree: return panic("YAML shared subtree rejected")

test "YAML stringify applies optional exact output depth and value budgets":
    let tree = YamlValue.ArrayValue([YamlValue.StringValue("é")])
    let limited: Result[String, YamlError] = error(YamlError.LimitExceeded)
    let invalid: Result[String, YamlError] = error(YamlError.InvalidInput)
    let limits = YamlLimits(max_bytes: 6, max_depth: 2, max_values: 2)
    if value(stringify(tree, limits)) != "[\"é\"]": return panic("YAML exact limits")
    if (
        stringify(
            tree,
            YamlLimits(max_bytes: 5, max_depth: none, max_values: none)
        ) != limited
    ): return panic("YAML UTF-8 output limit")
    if (
        stringify(
            tree,
            YamlLimits(max_bytes: none, max_depth: 1, max_values: none)
        ) != limited
    ): return panic("YAML depth limit")
    if (
        stringify(
            tree,
            YamlLimits(max_bytes: none, max_depth: none, max_values: 1)
        ) != limited
    ): return panic("YAML value limit")
    if (
        stringify(
            tree,
            YamlLimits(max_bytes: none, max_depth: -1, max_values: none)
        ) != invalid
    ): return panic("YAML negative limit")
    if (
        stringify(
            YamlValue.Null,
            YamlLimits(max_bytes: none, max_depth: 0, max_values: none)
        ) != limited
    ): return panic("YAML zero depth")
