// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	YamlValue, parse from "@std/data/yaml.ms",
	expect_equal, expect_error, expect_ok, fail from "@std/test/test.ms",
)

fn invalid(source: String) Unit!:
	cause := parse(source) | expect_error?
	if cause.kind == "EBADMSG": return ok(unit)

	return fail("expected malformed YAML, got {cause}")

test "YAML unquoted block keys reject reserved leading indicators":
	for key in ["]key", "\}key", ",key", "@key", "`key", "|key", ">key"]:
		invalid("{key}: value")?
		invalid("good: value\n{key}: value")?

	invalid("good: value\n%key: value")?

test "YAML quoted block keys preserve indicator prefixes":
	for key in ["]key", "\}key", ",key", "@key", "`key", "|key", ">key"]:
		var values = Map[String, YamlValue]()
		values.add(key.clone(), YamlValue.StringValue("value"))
		(
			parse("\"{key}\": value") | expect_ok? | expect_equal(
				YamlValue.ObjectValue(values)
			)?
		)

test "YAML a question mark followed by a letter is a plain block key":
	var values = Map[String, YamlValue]()
	values.add("?key", YamlValue.StringValue("value"))
	(parse("?key: value") | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?)

test "YAML explicit and complex mapping keys remain unsupported":
	for source in ["? key\n: value", "[key]: value"]:
		cause := parse(source) | expect_error?
		if cause.kind != "ENOTSUP":
			return fail("expected unsupported mapping key, got {cause}")
