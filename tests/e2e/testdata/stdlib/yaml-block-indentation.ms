import (
	YamlValue, parse from "@std/data/yaml.ms",
	expect_equal from "@std/test/test.ms",
)

fn text(source: String, expected: String) Unit!:
	expect_equal((parse(source)?), YamlValue.StringValue(expected))?

fn field(source: String, expected: String) Unit!:
	want := YamlValue.ObjectValue({"value": YamlValue.StringValue(expected)})
	expect_equal((parse(source)?), want)?

test "YAML root indentation indicators start at column zero":
	for prefix in ["", "  ", "---\n", "&anchor "]:
		text("{prefix}|2\n  one\n  two\n", "one\ntwo\n")?
		text("{prefix}>2\n  one\n  two\n", "one two\n")?

	text("&anchor\n|2\n  one\n", "one\n")?
	text("|1-\n one\n", "one")?
	text("|3+\n   one\n\n", "one\n\n")?
	text("|2-\n    indented\n  ordinary\n", "  indented\nordinary")?

test "YAML standalone block headers retain their containing mapping base":
	field("value: |2\n  one\n", "one\n")?
	field("value:\n  |2\n  one\n", "one\n")?
	field("value:\n    >2\n  one\n  two\n", "one two\n")?
	field("value: &anchor\n  |2\n    one\n", "  one\n")?
	field("value:\n  &anchor\n  |2\n  one\n", "one\n")?

	nested := YamlValue.ObjectValue(
		{
			"outer": YamlValue.ObjectValue(
				{"value": YamlValue.StringValue("one two\n")}
			)
		}
	)
	expect_equal((parse("outer:\n  value:\n    >2\n    one\n    two\n")?), nested)?

test "YAML standalone block headers retain their containing sequence base":
	want := YamlValue.ArrayValue([YamlValue.StringValue("one two\n")])
	for source in ["- >2\n  one\n  two\n", "-\n  >2\n  one\n  two\n"]:
		expect_equal((parse(source)?), want)?

	nested := YamlValue.ArrayValue(
		[YamlValue.ArrayValue([YamlValue.StringValue("one\n")])]
	)
	expect_equal((parse("- -\n    |2\n    one\n")?), nested)?

test "YAML automatic indentation and plain continuations stay unchanged":
	text("|\n  one\n  two\n", "one\ntwo\n")?
	text(">\n  one\n  two\n", "one two\n")?
	text("  |\n one\n", "one\n")?
	field("value:\n  |\n one\n", "one\n")?
	text("one\ntwo\n", "one two")?
	field("value:\n  one\n  two\n", "one two")?
	field("value:\n  |\n    one\n", "one\n")?

test "YAML block content must exceed its containing indentation":
	for source in ["|\na\n", "value:\n  |\na\n", "-\n  |\na\n"]:
		expect_equal(parse(source).is_error(), true)?

test "YAML implicit indentation rejects overindented leading empty lines":
	for style in ["|", ">", "|-", ">+"]:
		expect_equal(parse("{style}\n  \n a\n").is_error(), true)?
		expect_equal(parse("value: {style}\n   \n  a\n").is_error(), true)?
		expect_equal(parse("- {style}\n   \n  a\n").is_error(), true)?

	text("|\n \n  a\n", "\na\n")?
	text("|\n  \n  a\n", "\na\n")?
	text("|1\n  \n a\n", " \na\n")?
	text("|\n  \n", "")?
	expect_equal(
		(parse("value: |\n   \nnext: word\n")?),
		YamlValue.ObjectValue(
			{
				"value": YamlValue.StringValue(""),
				"next": YamlValue.StringValue("word")
			}
		)
	)?

test "YAML version directive composes with same-line document content":
	for header in ["%YAML 1.2", "%YAML 1.2 # supported"]:
		text("{header}\n--- word\n", "word")?
		field("{header}\n--- \{value: word\}\n", "word")?
		text("{header}\n--- |2\n  word\n", "word\n")?
		text("{header}\n--- # comment\nword\n", "word")?
		text("{header}\n---\nword\n", "word")?
		expect_equal(parse("{header}\nword\n").is_error(), true)?
		expect_equal(parse("{header}\n---word\n").is_error(), true)?

	expect_equal(parse("%YAML 1.1\n--- word\n").is_error(), true)?
