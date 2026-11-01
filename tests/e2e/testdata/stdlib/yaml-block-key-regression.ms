import expect_equal, expect_error, expect_ok, fail from "@std/test/test.ms"
import parse, YamlValue from "@std/data/yaml.ms"

fn invalid(source: String) Unit!:
    let cause = parse(source) | try expect_error

    match cause:
        InvalidData(_, _, _): return ok(unit)
        _: return fail("expected malformed YAML, got {cause}")

test "YAML unquoted block keys reject reserved leading indicators":
    for key in ["]key", "\}key", ",key", "@key", "`key", "|key", ">key"]:
        try invalid("{key}: value")
        try invalid("good: value\n{key}: value")

    try invalid("good: value\n%key: value")

test "YAML quoted block keys preserve indicator prefixes":
    for key in ["]key", "\}key", ",key", "@key", "`key", "|key", ">key"]:
        var values = Map[String, YamlValue]()
        values.add(key.clone(), YamlValue.StringValue("value"))
        parse("\"{key}\": value") | try expect_ok | try expect_equal(
            YamlValue.ObjectValue(values)
        )

test "YAML a question mark followed by a letter is a plain block key":
    var values = Map[String, YamlValue]()
    values.add("?key", YamlValue.StringValue("value"))
    parse("?key: value") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML explicit and complex mapping keys remain unsupported":
    for source in ["? key\n: value", "[key]: value"]:
        let cause = parse(source) | try expect_error

        match cause:
            UnsupportedFeature(_, _): unit
            _: return fail("expected unsupported mapping key, got {cause}")
