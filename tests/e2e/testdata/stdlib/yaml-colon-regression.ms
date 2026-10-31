import expect_equal, expect_ok, expect_true from "@std/test.ms"
import parse, YamlValue from "@std/yaml.ms"

fn object(keys: List[String], values: List[YamlValue]) YamlValue:
    var result = Map[String, YamlValue]()
    for i in 0..keys.length(): result.add(keys.get(i).clone(), values.get(i).clone())
    return YamlValue.ObjectValue(result)

test "YAML flow plain keys retain nonseparating colons":
    let source = "\{a:1, key:\"word\", url:http://example.org\}"
    let expected = object(
        ["a:1", "key:\"word\"", "url:http://example.org"],
        [YamlValue.Null, YamlValue.Null, YamlValue.Null]
    )
    parse(source) | try expect_ok | try expect_equal(expected)
    parse("\{http://example.org/path: value\}") | try expect_ok | try expect_equal(
        object(["http://example.org/path"], [YamlValue.StringValue("value")])
    )

test "YAML flow colon separators retain quoted and empty values":
    for source in [
        "\{a: word\}", "\{a:\tword\}", "\{a:\n word\}", "\{\"a\":word\}", "\{'a':word\}"
    ]:
        parse(source) | try expect_ok | try expect_equal(
            object(["a"], [YamlValue.StringValue("word")])
        )
    for source in ["\{a:\}", "\{a:,\}"]:
        parse(source) | try expect_ok | try expect_equal(
            object(["a"], [YamlValue.Null])
        )
    parse("\{a:[1]\}") | try expect_ok | try expect_equal(
        object(["a"], [YamlValue.ArrayValue([YamlValue.NumberValue("1")])])
    )
    parse("\{a:\{b: 2\}\}") | try expect_ok | try expect_equal(
        object(["a"], [object(["b"], [YamlValue.NumberValue("2")])])
    )
    parse("\{a:]\}").is_error() | try expect_true
