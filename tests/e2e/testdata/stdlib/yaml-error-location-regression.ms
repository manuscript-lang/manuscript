import (
	YamlValue, parse from "@std/data/yaml.ms",
	expect_equal, expect_error, expect_ok, fail from "@std/test/test.ms",
)

fn error_at(text: String, line: Int, column: Int) Unit!Error:
	cause := parse(text) | expect_error?
	if cause.kind != "EBADMSG": return fail("expected InvalidData, got {cause}")

	expect_equal(cause.details["line"], line.to_string())?
	expect_equal(cause.details["column"], column.to_string())?

test "YAML root EOF location control":
	error_at("[one", 1, 5)?

test "YAML flow EOF columns include mapping prefixes":
	error_at("key: [one", 1, 10)?
	error_at("clé: [é", 1, 8)?

test "YAML flow EOF location follows physical source lines":
	error_at("key: [one,\n two", 2, 5)?
	error_at("key: [one, # comment\n two", 2, 5)?

test "YAML flow EOF columns retain compact and anchor prefixes":
	error_at("- [one", 1, 7)?
	error_at("- key: [one", 1, 12)?
	error_at("- - [one", 1, 9)?
	error_at("&a [one", 1, 8)?
	error_at("key: &", 1, 7)?
	error_at("--- &", 1, 6)?

test "YAML quoted EOF location retains root indentation":
	error_at("  \"one", 1, 7)?
	error_at("  \"é", 1, 5)?
	error_at("  \"é\\q\": value", 1, 7)?

test "YAML inline document content retains its source row":
	error_at("--- [one", 1, 9)?
	error_at("--- [one,\n two", 2, 5)?
	error_at("# note\n--- [one", 2, 9)?
	error_at("---\n-\t\tkey: [one", 2, 13)?

test "YAML compact tab rewrites retain original scalar columns":
	error_at("-\t\tkey: [one", 1, 13)?
	error_at("- \t key: [one", 1, 14)?
	error_at("-\t\t-\t\tkey: [one", 1, 16)?
	error_at("-\t\tkey: ok\n- key: [one", 2, 12)?

fn unsupported_at(text: String, line: Int) Unit!Error:
	cause := parse(text) | expect_error?
	if cause.kind != "ENOTSUP": return fail("expected UnsupportedFeature, got {cause}")

	expect_equal(cause.details["line"], line.to_string())?

test "YAML flow merge failures retain their source origin":
	error_at("key: \{<<: 1\}", 1, 12)?
	error_at("key: \{\n  <<: 1\n\}", 2, 8)?

test "YAML unsupported flow nodes report their physical source line":
	unsupported_at("key: [one,\n !example x]", 2)?
	unsupported_at("key: \{\n [one]: x\}", 2)?
	unsupported_at("key: [first,\n ? unsupported\n tail]", 2)?

test "YAML invalid controls report their physical source position":
	error_at("first: ok\nsecond: bad\u{1}", 2, 12)?
	error_at("clé: ok\nx: é\u{1}", 2, 5)?
	error_at("x: é\u{1}\nlater: \u{1}", 1, 5)?
	error_at("first: ok\r\nx: é\u{81}", 2, 5)?

test "YAML inline document headers and merges retain source origins":
	error_at("--- |bad\n  x", 1, 6)?
	error_at("--- \{<<: 1\}", 1, 11)?

test "YAML source projection preserves compact document values":
	var values = Map[String, YamlValue]()
	values.add("key", YamlValue.StringValue("value"))

	expected := YamlValue.ArrayValue([YamlValue.ObjectValue(values)])
	parse("-\t\tkey: value") | expect_ok? | expect_equal(expected)?
	parse("---\n-\t\tkey: value") | expect_ok? | expect_equal(expected)?
	parse("-\t\t-\t\tkey: value") | expect_ok? | expect_equal(
		YamlValue.ArrayValue([expected.clone()])
	)?

test "YAML block header origins distinguish identical quoted key text":
	error_at("\"|bad\": |bad\n  x", 1, 10)?
	error_at("---\n\"|bad\": |bad\n  x", 2, 10)?
