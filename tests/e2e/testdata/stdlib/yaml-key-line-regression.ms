import expect_equal, expect_error, expect_ok, fail from "@std/test/test.ms"
import parse, YamlValue from "@std/data/yaml.ms"

fn invalid(source: String) Unit!:
    let cause = parse(source) | try expect_error
    if cause.kind != ErrorCategory.InvalidData:
        return fail("expected malformed implicit key, got {cause}")

    cause.details["reason"] | try expect_equal(
        "an implicit mapping key must stay on one line"
    )
    return ok(unit)

test "YAML plain implicit keys cannot span physical lines":
    for source in ["\{key\n next: value\}", "\{key\n: value\}"]:
        try invalid(source)

test "YAML quoted implicit keys cannot span physical lines":
    for source in [
        "\{'key\n next': value\}", "\{\"key\n next\": value\}",
        "\{\"key\\\n next\": value\}", "\{\"key\"\n: value\}"
    ]:
        try invalid(source)

test "YAML quoted implicit keys may contain escaped newline text":
    var values = Map[String, YamlValue]()
    values.add("key\nnext", YamlValue.StringValue("value"))
    parse("\{\"key\\nnext\": value\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML omitted flow values retain multiline node and entry separation":
    for source in ["\{key\n next\}", "\{\"key\n next\"\}"]:
        var values = Map[String, YamlValue]()
        values.add("key next", YamlValue.Null)
        parse(source) | try expect_ok | try expect_equal(YamlValue.ObjectValue(values))

    for source in ["\{key\n, next: value\}", "\{\"key\"\n, next: value\}"]:
        var values = Map[String, YamlValue]()
        values.add("key", YamlValue.Null)
        values.add("next", YamlValue.StringValue("value"))
        parse(source) | try expect_ok | try expect_equal(YamlValue.ObjectValue(values))

test "YAML flow values can begin on the line after their colon":
    var values = Map[String, YamlValue]()
    values.add("key", YamlValue.StringValue("value"))
    parse("\{key:\n value\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )
