import expect_equal, expect_error, expect_ok, expect_true, fail from "@std/test/test.ms"
import parse, YamlValue, YamlError from "@std/data/yaml.ms"

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

fn invalid(source: String) Unit!:
    let cause = parse(source) | try expect_error

    match cause:
        InvalidData(_, _, reason):
            reason | try expect_equal("unexpected mapping colon")
            return ok(unit)
        _: return fail("expected malformed YAML, got {cause}")

test "YAML flow scalar rejects a colon before tab":
    try invalid("\{a: x:\tb\}")

test "YAML flow scalar rejects a colon before newline":
    try invalid("\{a: x:\nb\}")

test "YAML flow scalar rejects a colon before a closing mapping":
    try invalid("\{a: x:\}")

test "YAML block scalar rejects an embedded mapping separator":
    try invalid("a: x:\tb")

test "YAML block scalar rejects a trailing mapping separator":
    try invalid("a: x:")

test "YAML block plain scalars retain nonseparating colons and punctuation":
    for text in ["http://example.org/path", "x:]", "x:[word]", "x:\{word\}"]:
        parse("a: {text}") | try expect_ok | try expect_equal(
            object(["a"], [YamlValue.StringValue(text.clone())])
        )

test "YAML block scalar rejects a separator before a folded paragraph break":
    try invalid("a: x:\n\n  b")
