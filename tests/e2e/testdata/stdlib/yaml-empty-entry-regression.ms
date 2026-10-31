import expect_equal, expect_error, expect_ok, fail from "@std/test.ms"
import parse, YamlValue from "@std/yaml.ms"

test "YAML flow mappings reject empty comma entries":
    for source in [
        "\{,\}", "\{, key: value\}", "\{key: value,, next: value\}", "[\{,\}]",
        "\{key,,\}"
    ]:
        let cause = parse(source) | try expect_error

        match cause:
            InvalidData(_, _, reason): reason | try expect_equal(
                "expected flow mapping key"
            )
            _: return fail("expected malformed flow entry, got {cause}")

test "YAML flow mappings retain legal trailing commas":
    var values = Map[String, YamlValue]()
    values.add("key", YamlValue.StringValue("value"))
    parse("\{key: value,\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

    var nulls = Map[String, YamlValue]()
    nulls.add("key", YamlValue.Null)
    parse("\{key,\}") | try expect_ok | try expect_equal(YamlValue.ObjectValue(nulls))

test "YAML flow mappings retain existing empty-key forms":
    for source in ["\{\"\": value\}", "\{: value\}"]:
        var values = Map[String, YamlValue]()
        values.add("", YamlValue.StringValue("value"))
        parse(source) | try expect_ok | try expect_equal(YamlValue.ObjectValue(values))
