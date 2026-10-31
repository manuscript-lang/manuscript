import expect_equal, expect_error, expect_ok, fail from "@std/test.ms"
import parse, YamlValue from "@std/yaml.ms"

fn error_at(text: String, line: Int, column: Int) Unit!Error:
    let cause = parse(text) | try expect_error

    match cause:
        InvalidData(found_line, found_column, _):
            try expect_equal(found_line, line)
            try expect_equal(found_column, column)
        _: return fail("expected InvalidData, got {cause}")

    return ok(unit)

test "YAML root EOF location control":
    try error_at("[one", 1, 5)

test "YAML flow EOF columns include mapping prefixes":
    try error_at("key: [one", 1, 10)
    try error_at("clé: [é", 1, 8)

test "YAML flow EOF location follows physical source lines":
    try error_at("key: [one,\n two", 2, 5)
    try error_at("key: [one, # comment\n two", 2, 5)

test "YAML flow EOF columns retain compact and anchor prefixes":
    try error_at("- [one", 1, 7)
    try error_at("- key: [one", 1, 12)
    try error_at("- - [one", 1, 9)
    try error_at("&a [one", 1, 8)
    try error_at("key: &", 1, 7)
    try error_at("--- key: &", 1, 11)

test "YAML quoted EOF location retains root indentation":
    try error_at("  \"one", 1, 7)
    try error_at("  \"é", 1, 5)
    try error_at("  \"é\\q\": value", 1, 7)

test "YAML inline document content retains its source row":
    try error_at("--- [one", 1, 9)
    try error_at("--- [one,\n two", 2, 5)
    try error_at("# note\n--- [one", 2, 9)
    try error_at("--- -\t\tkey: [one", 1, 17)

test "YAML compact tab rewrites retain original scalar columns":
    try error_at("-\t\tkey: [one", 1, 13)
    try error_at("- \t key: [one", 1, 14)
    try error_at("-\t\t-\t\tkey: [one", 1, 16)
    try error_at("-\t\tkey: ok\n- key: [one", 2, 12)

fn unsupported_at(text: String, line: Int) Unit!Error:
    let cause = parse(text) | try expect_error

    match cause:
        UnsupportedFeature(found_line, _): try expect_equal(found_line, line)
        _: return fail("expected UnsupportedFeature, got {cause}")

    return ok(unit)

test "YAML flow merge failures retain their source origin":
    try error_at("key: \{<<: 1\}", 1, 12)
    try error_at("key: \{\n  <<: 1\n\}", 2, 8)

test "YAML unsupported flow nodes report their physical source line":
    try unsupported_at("key: [one,\n !example x]", 2)
    try unsupported_at("key: \{\n [one]: x\}", 2)
    try unsupported_at("key: [first,\n ? unsupported\n tail]", 2)

test "YAML invalid controls report their physical source position":
    try error_at("first: ok\nsecond: bad\u{1}", 2, 12)
    try error_at("clé: ok\nx: é\u{1}", 2, 5)
    try error_at("x: é\u{1}\nlater: \u{1}", 1, 5)
    try error_at("first: ok\r\nx: é\u{81}", 2, 5)

test "YAML inline document headers and merges retain source origins":
    try error_at("--- key: |bad\n  x", 1, 11)
    try error_at("--- <<: 1", 1, 5)

test "YAML source projection preserves compact document values":
    var values = Map[String, YamlValue]()
    values.add("key", YamlValue.StringValue("value"))

    let expected = YamlValue.ArrayValue([YamlValue.ObjectValue(values)])
    parse("-\t\tkey: value") | try expect_ok | try expect_equal(expected)
    parse("--- -\t\tkey: value") | try expect_ok | try expect_equal(expected)
    parse("-\t\t-\t\tkey: value") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue([expected.clone()])
    )

test "YAML block header origins distinguish identical quoted key text":
    try error_at("\"|bad\": |bad\n  x", 1, 10)
    try error_at("--- \"|bad\": |bad\n  x", 1, 14)
