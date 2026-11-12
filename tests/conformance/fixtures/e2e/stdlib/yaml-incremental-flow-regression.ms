// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	YamlValue, parse from "@std/data/yaml.ms",
	StringBuilder from "@std/string.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type FoldControl:
	input: String
	output: String

test "YAML long multiline flow retains every scalar":
	var source = StringBuilder()
	var expected: List[YamlValue] = []
	source.append("[")

	for i in 0..2000:
		if i > 0: source.append(",")
		source.append("\n{i}")
		expected.append(YamlValue.NumberValue(i.to_string()))

	source.append("]")
	(parse(source.build()) | expect_ok? | expect_equal(YamlValue.ArrayValue(expected))?)
	for control in [
		FoldControl(input: "[alpha\n beta]", output: "alpha beta"),
		FoldControl(input: "[alpha\n\n beta]", output: "alpha\nbeta"),
		FoldControl(input: "[alpha\n\n\n beta]", output: "alpha\n\nbeta"),
		FoldControl(input: "[\n alpha\n beta\n]", output: "alpha beta"),
		FoldControl(input: "[日付\n 🙂]", output: "日付 🙂"),
	]:
		expect_equal(
			parse(control.input)?,
			YamlValue.ArrayValue([YamlValue.StringValue(control.output)]),
		)?

test "YAML flow scanner carries anchors and quoted markers across lines":
	(
		parse("[&one\n \"a # kept\", *one]")
		| expect_ok?
		| expect_equal(
			YamlValue.ArrayValue(
				[
					YamlValue.StringValue("a # kept"),
					YamlValue.StringValue("a # kept"),
				]
			)
		)?
	)

test "YAML multiline quoted nodes keep escapes and doubled quotes":
	(
		parse("[\"a\\\n b\", 'it''s\n fine']")
		| expect_ok?
		| expect_equal(
			YamlValue.ArrayValue(
				[
					YamlValue.StringValue("ab"),
					YamlValue.StringValue("it's fine"),
				]
			)
		)?
	)

test "YAML flow comment offsets remain scalar based":
	(
		parse("[é, # ignored '\"[\n🙂, # ignored ]\n last]")
		| expect_ok?
		| expect_equal(
			YamlValue.ArrayValue(
				[
					YamlValue.StringValue("é"),
					YamlValue.StringValue("🙂"),
					YamlValue.StringValue("last"),
				]
			)
		)?
	)
