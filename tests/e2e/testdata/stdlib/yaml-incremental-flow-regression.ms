import (
	expect_equal, expect_ok from "@std/test/test.ms",
	parse, YamlValue from "@std/data/yaml.ms",
	StringBuilder from "@std/string.ms",
)

test "YAML long multiline flow retains every scalar":
	var source = StringBuilder()
	var expected: List[YamlValue] = []
	source.append("[")

	for i in 0..2000:
		if i > 0: source.append(",")
		source.append("\n{i}")
		expected.append(YamlValue.NumberValue(i.to_string()))

	source.append("]")
	parse(source.build()) | try expect_ok | try expect_equal(
		YamlValue.ArrayValue(expected)
	)

test "YAML flow scanner carries anchors and quoted markers across lines":
	parse("[&one\n \"a # kept\", *one]") | try expect_ok | try expect_equal(
		YamlValue.ArrayValue(
			[
				YamlValue.StringValue("a # kept"), YamlValue.StringValue("a # kept")
			]
		)
	)

test "YAML multiline quoted nodes keep escapes and doubled quotes":
	parse("[\"a\\\n b\", 'it''s\n fine']") | try expect_ok | try expect_equal(
		YamlValue.ArrayValue(
			[
				YamlValue.StringValue("ab"), YamlValue.StringValue("it's fine")
			]
		)
	)

test "YAML flow comment offsets remain scalar based":
	parse("[é, # ignored '\"[\n🙂, # ignored ]\n last]") | try expect_ok | try expect_equal(
		YamlValue.ArrayValue(
			[
				YamlValue.StringValue("é"), YamlValue.StringValue("🙂"),
				YamlValue.StringValue("last")
			]
		)
	)
