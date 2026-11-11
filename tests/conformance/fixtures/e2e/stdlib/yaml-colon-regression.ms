// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	YamlValue, parse from "@std/data/yaml.ms",
	expect_equal, expect_error, expect_ok, expect_true, fail from "@std/test/test.ms",
)

fn object(keys: List[String], values: List[YamlValue]) YamlValue:
	var result = Map[String, YamlValue]()
	for i in 0..keys.length(): result.add(keys.get(i).clone(), values.get(i).clone())
	return YamlValue.ObjectValue(result)

test "YAML flow plain keys retain nonseparating colons":
	source := "\{a:1, key:\"word\", url:http://example.org\}"
	expected := object(
		["a:1", "key:\"word\"", "url:http://example.org"],
		[YamlValue.Null, YamlValue.Null, YamlValue.Null],
	)
	(parse(source) | expect_ok? | expect_equal(expected)?)
	(
		parse("\{http://example.org/path: value\}") | expect_ok? | expect_equal(
			object(
				["http://example.org/path"],
				[YamlValue.StringValue("value")],
			)
		)?
	)

test "YAML flow colon separators retain quoted and empty values":
	for source in [
		"\{a: word\}", "\{a:\tword\}", "\{a:\n word\}", "\{\"a\":word\}", "\{'a':word\}"
	]:
		(
			parse(source)
			| expect_ok?
			| expect_equal(object(["a"], [YamlValue.StringValue("word")]))?
		)
	for source in ["\{a:\}", "\{a:,\}"]:
		(
			parse(source)
			| expect_ok?
			| expect_equal(object(["a"], [YamlValue.Null]))?
		)
	(
		parse("\{a:[1]\}") | expect_ok? | expect_equal(
			object(
				["a"],
				[YamlValue.ArrayValue([YamlValue.NumberValue("1")])],
			)
		)?
	)
	(
		parse("\{a:\{b: 2\}\}") | expect_ok? | expect_equal(
			object(["a"], [object(["b"], [YamlValue.NumberValue("2")])])
		)?
	)
	parse("\{a:]\}").is_error() | expect_true?

fn invalid(source: String) Unit!:
	cause := parse(source) | expect_error?
	if cause.kind != "EBADMSG": return fail("expected malformed YAML, got {cause}")

	cause.details["reason"] | expect_equal("unexpected mapping colon")?

test "YAML flow scalar rejects a colon before tab":
	invalid("\{a: x:\tb\}")?

test "YAML flow scalar rejects a colon before newline":
	invalid("\{a: x:\nb\}")?

test "YAML flow scalar rejects a colon before a closing mapping":
	invalid("\{a: x:\}")?

test "YAML block scalar rejects an embedded mapping separator":
	invalid("a: x:\tb")?

test "YAML block scalar rejects a trailing mapping separator":
	invalid("a: x:")?

test "YAML block plain scalars retain nonseparating colons and punctuation":
	for text in ["http://example.org/path", "x:]", "x:[word]", "x:\{word\}"]:
		(
			parse("a: {text}")
			| expect_ok?
			| expect_equal(
				object(["a"], [YamlValue.StringValue(text.clone())])
			)?
		)

test "YAML block scalar rejects a separator before a folded paragraph break":
	invalid("a: x:\n\n  b")?
