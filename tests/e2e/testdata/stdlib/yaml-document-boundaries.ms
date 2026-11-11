import (
	YamlValue, parse from "@std/data/yaml.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

test "same-line document content cannot be a block collection":
	for body in [
		"value: word", "- word", "-", "\"key\": word", "&name value: word",
		"  value: word", "  - word"
	]:
		expect_equal(parse("--- {body}\n").is_error(), true)?
		expect_equal(parse("%YAML 1.2\n--- {body}\n").is_error(), true)?

test "inline flow and scalar document content stays supported":
	for body in ["word", "\"word\"", "'word'", "&name word"]:
		expect_equal((parse("--- {body}\n")?), YamlValue.StringValue("word"))?
	expect_equal(
		(parse("--- \"value: word\"\n")?), YamlValue.StringValue("value: word")
	)?
	expect_equal((parse("--- \"- word\"\n")?), YamlValue.StringValue("- word"))?
	expect_equal((parse("--- \{value: word\}\n")?), (parse("value: word\n")?))?
	expect_equal((parse("--- [word]\n")?), (parse("- word\n")?))?
	expect_equal((parse("--- |\n  word\n")?), YamlValue.StringValue("word\n"))?

test "anchored inline flow collection stays supported":
	expect_equal((parse("--- &name \{value: word\}\n")?), (parse("value: word\n")?))?

test "block collections following the physical marker line stay supported":
	for prefix in ["---\n", "--- # comment\n", "--- &name\n", "%YAML 1.2\n--- &name\n"]:
		expect_equal((parse("{prefix}value: word\n")?), (parse("value: word\n")?))?
		expect_equal((parse("{prefix}- word\n")?), (parse("- word\n")?))?

test "same-line block collection errors retain physical locations":
	first := parse("--- value: word\n")
	expect_equal(first.is_error(), true)?
	expect_equal(first.err().details.get("line"), "1")?
	expect_equal(first.err().details.get("column"), "5")?

	second := parse("%YAML 1.2\n--- - word\n")
	expect_equal(second.is_error(), true)?
	expect_equal(second.err().details.get("line"), "2")?
	expect_equal(second.err().details.get("column"), "5")?

test "document markers cannot continue flow collections or quoted scalars":
	for marker in ["---", "..."]:
		for suffix in ["", " ", " # boundary", "\t# boundary"]:
			for prefix in ["[", "[word,", "\{key:", "\"word", "'word"]:
				closing := if prefix == "'word": "'" else if prefix == "\"word": "\"" else if prefix == "\{key:": "\}" else: "]"
				cause := parse("{prefix}\n{marker}{suffix}\n{closing}") | expect_error?
				expect_equal(cause.kind, "EBADMSG")?
				expect_equal(cause.details["line"], "2")?
				expect_equal(cause.details["column"], "1")?

test "flow document boundary errors retain physical source rows":
	for source in [
		"--- [\n# comment\n---\n]", "--- \"word\n# quoted text\n...\n\"",
		"- key: [\n# comment\n---\n]"
	]:
		cause := parse(source) | expect_error?
		expect_equal(cause.kind, "EBADMSG")?
		expect_equal(cause.details["line"], "3")?
		expect_equal(cause.details["column"], "1")?

test "quoted escapes and normalized line endings retain document boundaries":
	for ending in ["\n", "\r\n", "\r"]:
		for prefix in ["\"word", "\"word\\", "'word"]:
			closing := if prefix == "'word": "'" else: "\""
			source := "{prefix}\n---\n{closing}".replace("\n", ending)
			cause := parse(source) | expect_error?
			expect_equal(cause.kind, "EBADMSG")?
			expect_equal(cause.details["line"], "2")?
			expect_equal(cause.details["column"], "1")?

test "tab separated document markers end plain scalar continuation":
	for marker in ["---", "..."]:
		cause := parse("word\n{marker}\tmore\n") | expect_error?
		expect_equal(cause.kind, "EBADMSG")?
		expect_equal(cause.details["line"], "2")?

test "indented markers and marker prefixes remain scalar content":
	for marker in ["---", "..."]:
		expect_equal(
			(parse("[\n {marker}\n]")?),
			YamlValue.ArrayValue([YamlValue.StringValue(marker.clone())])
		)?
		for quote in ["'", "\""]:
			expect_equal(
				(parse("{quote}word\n {marker}\n end{quote}")?),
				YamlValue.StringValue("word {marker} end")
			)?
		for suffix in ["word", "#literal", "\u{a0}word"]:
			expect_equal(
				(parse("[\n{marker}{suffix}\n]")?),
				YamlValue.ArrayValue(
					[YamlValue.StringValue("{marker}{suffix}")]
				)
			)?
		expect_equal(
			(parse("[\n{marker}]")?),
			YamlValue.ArrayValue([YamlValue.StringValue(marker.clone())])
		)?
