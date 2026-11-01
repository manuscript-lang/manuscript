import expect_equal, expect_error, expect_ok, fail from "@std/test/test.ms"
import parse, YamlValue from "@std/data/yaml.ms"

test "YAML quotes inside a plain scalar do not hide comments":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("plain 'x"))
    parse("a: plain 'x # comment") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML plain scalar comments end the document node":
    parse("x 'y # comment") | try expect_ok | try expect_equal(
        YamlValue.StringValue("x 'y")
    )

test "YAML plain flow quotes do not absorb later mapping members":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.ArrayValue([YamlValue.StringValue("plain 'x")]))
    values.add("next", YamlValue.StringValue("value"))
    parse("a: [plain 'x # comment\n]\nnext: value") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML whole-line flow comments are separation":
    parse("[\n# note\n1\n]") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue([YamlValue.NumberValue("1")])
    )

test "YAML quoted nodes retain comment markers with adjacent values":
    var values = Map[String, YamlValue]()
    values.add("key", YamlValue.StringValue("hash # kept"))
    parse("\{\"key\":\"hash # kept\"\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML anchor properties preserve quoted comment markers":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("hash # kept"))
    values.add("b", YamlValue.StringValue("hash # kept"))
    parse("a: &message \"hash # kept\"\nb: *message") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML comment contents do not open quotes or containers":
    var values = Map[String, YamlValue]()
    values.add(
        "a",
        YamlValue.ArrayValue(
            [YamlValue.NumberValue("1"), YamlValue.NumberValue("2")]
        )
    )
    values.add("next", YamlValue.StringValue("value"))
    parse("a: [1, # '\"[\{ unmatched\n 2]\nnext: value") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML Unicode spaces do not start quoted syntax":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("\u{a0}'text"))
    parse("a: \u{a0}'text # comment") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML brackets inside block plain text stay ordinary characters":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("word [literal"))
    values.add("next", YamlValue.StringValue("value"))
    parse("a: word [literal # comment\nnext: value") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML plain closing brackets do not hide malformed nested values":
    let cause = parse("word] [text]: \{value: 1\}\}") | try expect_error

    match cause:
        InvalidData(_, _, _): unit
        _: return fail("expected malformed YAML, got {cause}")
