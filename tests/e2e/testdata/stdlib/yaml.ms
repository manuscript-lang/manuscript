import (
	YamlOptions, YamlValue, parse, stringify from "@std/data/yaml.ms",
	from_scalars from "@std/string.ms",
	expect_equal,
	expect_error,
	expect_false,
	expect_ok,
	expect_true,
	fail from "@std/test/test.ms",
)

fn entries(value: YamlValue) Map[String, YamlValue]!:
	match value:
		ObjectValue(values): return ok(values)
		_: return error(Error("expected YAML mapping"))

fn items(value: YamlValue) List[YamlValue]!:
	match value:
		ArrayValue(values): return ok(values)
		_: return error(Error("expected YAML sequence"))

fn limits(bytes: Int?, depth: Int?, values: Int?) YamlOptions:
	return YamlOptions(max_bytes: bytes, max_depth: depth, max_values: values)

type ScalarCase:
	text: String
	expected: String

fn scalar(text: String, expected: String) Unit!:
	root := parse(text: text) | expect_ok? | entries?
	if root["a"] != YamlValue.StringValue(expected): return error(
		Error("scalar folding: {text}")
	)

test "YAML issue 133 folded paragraph":
	(scalar(text: "a: >\n  x\n  y\n\n  z\n", expected: "x y\nz\n")?)

test "YAML issue 133 folded multiple blank lines":
	(scalar(text: "a: >\n  x\n\n\n  z\n", expected: "x\n\nz\n")?)

test "YAML issue 133 single quoted paragraph":
	(scalar(text: "a: 'x\n\n  y'", expected: "x\ny")?)

test "YAML issue 133 double quoted paragraphs":
	(scalar(text: "a: \"x\n\n\n  y\"", expected: "x\n\ny")?)

test "YAML issue 133 plain paragraph before sibling":
	(scalar(text: "a: x\n\n  y\nb: 1", expected: "x\ny")?)

test "YAML quoted folding trims physical whitespace and preserves escapes":
	cases := [
		ScalarCase(text: "a: 'x \t\n \t\n  y'", expected: "x\ny"),
		ScalarCase(text: "a: \"x \t\n \t\n\n  y\"", expected: "x\n\ny"),
		ScalarCase(text: "a: ' x  \n  y '", expected: " x y "),
		ScalarCase(text: "a: \"x\\t\n  y\"", expected: "x\t y"),
		ScalarCase(text: "a: \"x\\ \n  y\"", expected: "x  y"),
		ScalarCase(text: "a: \"x \\\n  y\"", expected: "x y"),
		ScalarCase(text: "a: \"x \\\n \t\n\n  y\"", expected: "x \n\ny"),
		ScalarCase(
			text: "a: 'x\n\n  # hash: text\n\n  it''s y' # outside",
			expected: "x\n# hash: text\nit's y"
		),
		ScalarCase(
			text: "a: \"x\n\n  \\\"y\\\"\" # outside", expected: "x\n\"y\""
		)
	]
	for example in cases:
		for ending in ["\n", "\r\n", "\r"]:
			(
				scalar(
					text: (
						example
						.text
						.replace(old: "\n", new: ending)
					),
					expected: example.expected.clone()
				)?
			)
	parse(text: "'x\n\n  y'") | expect_ok? | expect_equal(YamlValue.StringValue("x\ny"))?

	flow := parse(text: "['x\n\n  y', \"z\\\n\n  w\"]") | expect_ok? | items?
	flow | expect_equal([YamlValue.StringValue("x\ny"), YamlValue.StringValue("z\nw")])?

test "YAML folded and literal blocks respect paragraphs indentation and chomping":
	cases := [
		ScalarCase(text: "a: >-\n  x\n \n  y\n\n", expected: "x\ny"),
		ScalarCase(text: "a: >\n  x\n\n  y\n\n\n", expected: "x\ny\n"),
		ScalarCase(text: "a: >+\n  x\n\n  y\n\n\n", expected: "x\ny\n\n\n"),
		ScalarCase(text: "a: >2-\n  x\n\n\n  y\n", expected: "x\n\ny"),
		ScalarCase(
			text: "a: >\n  x\n\n    y\n\n  z\n", expected: "x\n\n  y\n\nz\n"
		),
		ScalarCase(text: "a: >2-\n  x\n   \n  y\n", expected: "x\n \ny"),
		ScalarCase(
			text: "a: >2-\n  x\n\n  \ty\n\n  z\n", expected: "x\n\n\ty\n\nz"
		),
		ScalarCase(text: "a: >-\n\n  x\n\n  y\n", expected: "\nx\ny"),
		ScalarCase(text: "a: |\n  x\n\n  y\n", expected: "x\n\ny\n"),
		ScalarCase(text: "a: |+\n  x\n\n", expected: "x\n\n"),
		ScalarCase(text: "a: >\n  x", expected: "x"),
		ScalarCase(text: "a: |\n  x", expected: "x"),
		ScalarCase(text: "a: >+\n  x\n\n  y", expected: "x\ny"),
		ScalarCase(text: "a: >\n\n", expected: ""),
		ScalarCase(text: "a: >+\n\n", expected: "\n"),
		ScalarCase(text: "a: |-\n\n", expected: ""),
		ScalarCase(text: "a: >\n   \n", expected: ""),
		ScalarCase(text: "a: >+\n   \n", expected: "\n"),
		ScalarCase(text: "a: >2+\n   \n", expected: " \n"),
		ScalarCase(text: "a: >\n \t\n", expected: "\t\n")
	]
	for example in cases:
		for ending in ["\n", "\r\n", "\r"]:
			(
				scalar(
					text: (
						example
						.text
						.replace(old: "\n", new: ending)
					),
					expected: example.expected.clone()
				)?
			)

test "YAML plain paragraphs retain boundaries and nested collections":
	for ending in ["\n", "\r\n", "\r"]:
		text := "a: x  \n \t\n\n  y \t\n  z\n\nb: 1\n"
		root := (
			entries(
				(
					parse(
						text: text.replace(
							old: "\n", new: ending
						)
					) | expect_ok?
				)
			)?
		)
		root["a"] | expect_equal(YamlValue.StringValue("x\n\ny z"))?
		root["b"] | expect_equal(YamlValue.NumberValue("1"))?

	root := parse(text: "a:\n  - x\n\n    y\n  - z\nb: 1\n") | expect_ok? | entries?
	expect_false(
		(
			(items(root.get("a").get())?) != [
				YamlValue.StringValue("x\ny"), YamlValue.StringValue("z")
			]
		)
	)?
	(scalar(text: "a: x\n\n# comment\nb: 1\n", expected: "x")?)
	(scalar(text: "a: x\n\n", expected: "x")?)

test "YAML blank line folding retains byte node and malformed input contracts":
	text := "a: \"é\r\n\r\n  y\"\r\n"
	expected := (parse(text: text) | expect_ok?)
	expect_false(
		(
			(
				parse(
					text: text,
					options: limits(
						bytes: text.byte_length(), depth: 2, values: 2
					)
				) | expect_ok?
			) != expected
		)
	)?

	limited: YamlValue! := error(Error("YAML limit exceeded", kind: "EOVERFLOW"))
	expect_false(
		(
			parse(
				text: text,
				options: limits(
					bytes: text.byte_length() - 1, depth: none, values: none
				)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: text, options: limits(bytes: none, depth: none, values: 1)
			) != limited
		)
	)?

	for malformed in [
		"a: 'x\n\n  y", "a: \"x\n\n  y", "a: \"x\\\n\n  y\\q\"", "a: x\n\n  b: y",
		"a: x\n\n  - y", "a: x\n\n \ty", "a: x\n # comment\n  y", "a: >--\n\n  x",
		"a: >\n  x\n \t\n  y", "a: >2\n  x\n y"
	]:
		cause := match parse(text: malformed):
			ok(_): return fail("malformed multiline scalar accepted: {malformed}")
			error(cause): cause

		cause.kind | expect_equal("EBADMSG")?
		(
			(
				cause.details["line"].parse_int().get() < 1
				or cause.details["column"].parse_int().get() < 1
				or cause.details["reason"] == ""
			) | expect_false?
		)

	cause := match parse(text: "a: x\n\n  b: y"):
		error(cause): cause
		ok(_): return fail("indented mapping accepted as plain continuation")

	cause.kind | expect_equal("EBADMSG")?
	((cause.details["line"] != "3" or cause.details["column"] != "1") | expect_false?)

test "YAML block mappings sequences exact scalars and core schema":
	text := "name: é🙂\nlarge: 9007199254740993\nboolean: TRUE\nlegacy: yes\ndate: 2024-02-29\nempty:\nvalues:\n- null\n- false\n- 0xFF\npeople:\n  - name: Ada\n    age: 37\n  - name: Grace\n    skills:\n      - compilers\n"
	root := parse(text: text) | expect_ok? | entries?
	root["name"] | expect_equal(YamlValue.StringValue("é🙂"))?
	root["large"] | expect_equal(YamlValue.NumberValue("9007199254740993"))?
	root["boolean"] | expect_equal(YamlValue.BoolValue(true))?
	root["legacy"] | expect_equal(YamlValue.StringValue("yes"))?
	root["date"] | expect_equal(YamlValue.StringValue("2024-02-29"))?
	root["empty"] | expect_equal(YamlValue.Null)?
	expect_false(
		(
			(items(root.get("values").get())?) != [
				YamlValue.Null, YamlValue.BoolValue(false),
				YamlValue.NumberValue("0xFF")
			]
		)
	)?

	people := (items(root.get("people").get())?)
	expect_false(
		(
			people.length() != 2
			or (entries(people.first().get())?).get(
				"age"
			).get() != YamlValue.NumberValue("37")
		)
	)?
	expect_false(
		(
			(
				items(
					(entries(people.last().get())?).get(
						"skills"
					).get()
				)?
			).first().get() != YamlValue.StringValue("compilers")
		)
	)?

test "YAML flow collections quotes escapes comments and multiline values":
	root := (
		entries(
			(
				parse(
					text: "flow: \{name: 'it''s # fine', list: [true, 2, \"é\\u263A\",],\}\nurl: https://example.org/#fragment # comment\nquoted: \"hash # colon: brace \{\}\"\nmultiline: [1,\n  2, # comment\n  3]\ntext: a long\n  continued sentence\n"
				) | expect_ok?
			)
		)?
	)
	expect_false(
		(
			(entries(root.get("flow").get())?).get(
				"name"
			).get() != YamlValue.StringValue("it's # fine")
		)
	)?
	expect_false(
		(
			(
				items(
					(entries(root.get("flow").get())?).get(
						"list"
					).get()
				)?
			).last().get() != YamlValue.StringValue("é☺")
		)
	)?
	expect_false(
		(root["url"] != YamlValue.StringValue("https://example.org/#fragment"))
	)?
	(items(root.get("multiline").get())?).length() | expect_equal(3)?
	root["text"] | expect_equal(YamlValue.StringValue("a long continued sentence"))?
	parse(text: "'literal\\n'") | expect_ok? | expect_equal(
		YamlValue.StringValue("literal\\n")
	)?

test "YAML literal folded and chomped block scalars preserve content":
	root := (
		entries(
			(
				parse(
					text: "literal: |\n  first # text\n  second\nfolded: >-\n  hello\n  world\nkeep: |+\n  line\n\nexplicit: |2-\n  indented\ntabs: |-\n  \tcontent\n"
				) | expect_ok?
			)
		)?
	)
	(root["literal"] | expect_equal(YamlValue.StringValue("first # text\nsecond\n"))?)
	root["folded"] | expect_equal(YamlValue.StringValue("hello world"))?
	root["keep"] | expect_equal(YamlValue.StringValue("line\n\n"))?
	root["explicit"] | expect_equal(YamlValue.StringValue("indented"))?
	root["tabs"] | expect_equal(YamlValue.StringValue("\tcontent"))?

test "YAML anchors aliases merge keys and override precedence":
	text := "defaults: &defaults\n  retries: 3\n  enabled: true\ncopy: *defaults\nconfig:\n  <<: *defaults\n  retries: 5\nscalar: &answer 42\nalias: *answer\nflow: &flow [1, 2]\nflow_alias: *flow\n"
	root := parse(text: text) | expect_ok? | entries?
	root["defaults"] | expect_equal(root["copy"])?

	config := (entries(root.get("config").get())?)
	expect_false(
		(
			config["retries"] != YamlValue.NumberValue("5")
			or config["enabled"] != YamlValue.BoolValue(true)
		)
	)?
	root["alias"] | expect_equal(YamlValue.NumberValue("42"))?
	root["flow_alias"] | expect_equal((root["flow"]))?

	merged := (
		entries(
			(
				parse(
					text: "a: &a \{x: 1\}\nb: &b \{x: 2, y: 3\}\nc: \{<<: [*a, *b], y: 4\}\n"
				) | expect_ok?
			)
		)?
	)
	c := (entries(merged.get("c").get())?)
	expect_false(
		(
			c["x"] != YamlValue.NumberValue("1")
			or c["y"] != YamlValue.NumberValue("4")
		)
	)?

test "YAML documents BOM CRLF empty input and version directive":
	root := (
		parse(
			text: "\u{feff}%YAML 1.2\r\n---\r\na: 1\r\n...\r\n# done\r\n"
		) | expect_ok?
	)
	(entries(root)?)["a"] | expect_equal(YamlValue.NumberValue("1"))?
	parse(text: "# comment\n") | expect_ok? | expect_equal(YamlValue.Null)?
	parse(text: "---\n...\n") | expect_ok? | expect_equal(YamlValue.Null)?
	(items((parse(text: "- - 1\n  - 2\n- - 3\n") | expect_ok?))?).length() | expect_equal(
		2
	)?

test "YAML document markers end a root plain scalar":
	parse(text: "x\n...\n") | expect_ok? | expect_equal(YamlValue.StringValue("x"))?
	parse(text: "x\ny\n...\n") | expect_ok? | expect_equal(YamlValue.StringValue("x y"))?
	parse(text: "null\n...\n") | expect_ok? | expect_equal(YamlValue.Null)?
	expect_true(parse(text: "x\n---\ny\n").is_error())?

test "YAML plain scalars cannot start with an indicator":
	for text in [
		"a: - b\n", "a: -\n", "a: ? b\n", "a: @x\n", "a: `x\n", "a: ]\n", "a: ,\n",
		"a: %d\n", "- ? x\n"
	]:
		expect_true(parse(text: text).is_error())?

	_ := expect_ok(parse(text: "a: -1\nb: -a\nc: ?x\nd: [-1, ?y, :z]\n"))?
	explicit := parse(text: "\{? a : 1\}\n") | expect_error?
	explicit.kind | expect_equal("ENOTSUP")?
	explicit.details["line"] | expect_equal("1")?
	explicit.details["reason"] | expect_equal("explicit mapping keys are unsupported")?

test "YAML rejects duplicates invalid indentation malformed flow and aliases":
	for text in [
		"a: 1\na: 2", "\{a: 1, a: 2\}", "a:\n\tb: 1", "a: 1\n  b: 2",
		"a:\n  b: 1\n c: 2", "[1,", "[1,,2]", "\{a: 1 b: 2\}", "\"\\uD800\"", "\"\\q\"",
		"'unterminated", "*missing", "a: &loop [*loop]", "<<: 1",
		"---\na: 1\n---\nb: 2", "a: |0\n  text"
	]:
		cause := match parse(text: text):
			ok(_): return fail("invalid YAML accepted: {text}")
			error(cause): cause

		cause.kind | expect_equal("EBADMSG")?
		(
			(
				cause.details["line"].parse_int().get() < 1
				or cause.details["column"].parse_int().get() < 1
				or cause.details["reason"] == ""
			) | expect_false?
		)
		((cause.message.starts_with("YAML ")) | expect_true?)

	for text in [
		"!custom value", "? complex\n: value", "%TAG ! tag:example.org\n---\na: 1"
	]:
		cause := match parse(text: text):
			ok(_): return fail("unsupported YAML accepted")
			error(cause): cause

		cause.kind | expect_equal("ENOTSUP")?

test "YAML limits cover root nested nodes aliases and exact bytes":
	limited: YamlValue! := error(Error("YAML limit exceeded", kind: "EOVERFLOW"))
	invalid: YamlValue! := error(Error("invalid YAML input", kind: "EINVAL"))
	expect_false(
		(
			parse(
				text: "é", options: limits(bytes: 1, depth: none, values: none)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "[[[]]]", options: limits(bytes: none, depth: 2, values: none)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "a:\n  b: 1", options: limits(bytes: none, depth: 2, values: none)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "[1,2]", options: limits(bytes: none, depth: none, values: 2)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "a: &a [1,2]\nb: *a",
				options: limits(bytes: none, depth: none, values: 6)
			) != limited
		)
	)?
	expect_false(
		(
			parse(
				text: "", options: limits(bytes: 0, depth: 1, values: 1)
			) != parse(text: "")
		)
	)?
	parse(text: "", options: limits(bytes: none, depth: none, values: 0)) | expect_equal(
		limited
	)?
	expect_false(
		(
			parse(
				text: "", options: limits(bytes: none, depth: -1, values: none)
			) != invalid
		)
	)?
	expect_false(
		(
			parse(
				text: "[1,2]", options: limits(bytes: 5, depth: 2, values: 3)
			) != parse(text: "[1,2]")
		)
	)?

test "YAML exact decimal syntax does not depend on binary64 conversion":
	for text in [".5", "1.", "1.e2", "1e999999", ".Inf", ".NAN", "-0", "0001"]:
		if (parse(text: text) | expect_ok?) != YamlValue.NumberValue(text.clone()): return fail(
			"YAML number treated as string: {text}"
		)
	for text in [
		".", "1e", "1_000", "+0xFF", "-.nan", ".iNF", "it's plain",
		"text [with] punctuation"
	]:
		if (parse(text: text) | expect_ok?) != YamlValue.StringValue(text.clone()): return fail(
			"plain scalar resolved incorrectly: {text}"
		)

fn failure(text: String) String:
	match parse(text: text):
		ok(_): return "accepted"
		error(cause): return cause.message

test "YAML merge and block header errors name their own line":
	failure("<<: 1") | expect_equal("YAML 1:1: merge requires mappings")?
	failure("x: 1\ny: 2\n<<: 1") | expect_equal("YAML 3:1: merge requires mappings")?
	failure("a: |x") | expect_equal("YAML 1:5: invalid block scalar header")?
	failure("x: 1\ny: |x\nz: 3") | expect_equal("YAML 2:5: invalid block scalar header")?

test "YAML option fields default to none or the depth and value guards":
	limited: YamlValue! := error(Error("YAML limit exceeded", kind: "EOVERFLOW"))
	parse(text: "a: 1", options: YamlOptions(max_bytes: 2)) | expect_equal(limited)?
	parse(text: "a: 1", options: YamlOptions()) | expect_equal(parse(text: "a: 1"))?

test "YAML stringify round trips scalars sequences and mappings":
	source := "title: \"é🙂 \\\"q\\\" \\t tab\"\nnone: null\nflag: true\nint: -42\nfloat: 1.5e3\nlist:\n  - 1\n  - two\n  - [3, 4]\n  - a: 1\n    b: [x, y]\nempty_list: []\nempty_map: \{\}\n\"odd key\": 1\n\"true\": 2\nnested:\n  deep:\n    value: ok\n"
	parsed := (parse(text: source) | expect_ok?)
	text := (stringify(value: parsed) | expect_ok?)
	parse(text: text) | expect_ok? | expect_equal(parsed)?
	stringify(value: (parse(text: text) | expect_ok?)) | expect_ok? | expect_equal(text)?

test "YAML stringify validates numbers and honors max_bytes":
	invalid: String! := error(Error("invalid YAML input", kind: "EINVAL"))
	limited: String! := error(Error("YAML limit exceeded", kind: "EOVERFLOW"))
	stringify(value: YamlValue.NumberValue("not a number")) | expect_equal(invalid)?

	root := (parse(text: "a: 1") | expect_ok?)
	stringify(value: root, max_bytes: 3) | expect_equal(limited)?

	exact: String! := ok("a: 1\n")
	stringify(value: root, max_bytes: 5) | expect_equal(exact)?
	stringify(value: root, max_bytes: -1) | expect_equal(invalid)?

test "YAML scalars and anchors on their own line continue at the same indentation":
	folded := (
		entries(
			(
				parse(
					text: "run:\n  util/check.sh\n  --flag value\nnext: 1\n"
				) | expect_ok?
			)
		)?
	)
	expect_false((folded["run"] != YamlValue.StringValue("util/check.sh --flag value")))?
	folded["next"] | expect_equal(YamlValue.NumberValue("1"))?

	list := parse(text: "- foo\n  bar\n-\n  baz\n  qux\n") | expect_ok? | items?
	list | expect_equal(
		[YamlValue.StringValue("foo bar"), YamlValue.StringValue("baz qux")]
	)?

	anchored := parse(text: "a:\n  &x\n  k: 1\nb: *x\n") | expect_ok? | entries?
	anchored["a"] | expect_equal(anchored["b"])?
	expect_false(
		(
			(entries(anchored.get("b").get())?).get(
				"k"
			).get() != YamlValue.NumberValue("1")
		)
	)?

test "YAML quoted merge key is an ordinary string key":
	block := parse(text: "\"<<\": 1\nplain: 3\n") | expect_ok? | entries?
	block["<<"] | expect_equal(YamlValue.NumberValue("1"))?
	block.length() | expect_equal(2)?

	single := parse(text: "'<<': 2\n") | expect_ok? | entries?
	single["<<"] | expect_equal(YamlValue.NumberValue("2"))?

	flow := parse(text: "\{\"<<\": 1, a: 2\}\n") | expect_ok? | entries?
	flow["<<"] | expect_equal(YamlValue.NumberValue("1"))?

	merged := (
		entries(
			(
				parse(
					text: "base: &b \{x: 1\}\nm:\n  <<: *b\n  y: 2\n"
				) | expect_ok?
			)
		)?
	)
	expect_false(
		(
			(entries(merged.get("m").get())?).get(
				"x"
			).get() != YamlValue.NumberValue("1")
		)
	)?

	original := (parse(text: "\"<<\": 1\n") | expect_ok?)
	expect_equal(
		(parse(text: (stringify(value: original) | expect_ok?)) | expect_ok?), original
	)?

test "YAML plain scalars continued inside flow collections fold their line breaks":
	root := (
		entries(
			(
				parse(
					text: "a: [x\n  y, z]\nb: \{k: one\n    two\}\nc: [p\n  q\n\n  r]\n"
				) | expect_ok?
			)
		)?
	)
	expect_false(
		(
			(items(root.get("a").get())?) != [
				YamlValue.StringValue("x y"), YamlValue.StringValue("z")
			]
		)
	)?
	expect_false(
		(
			(entries(root.get("b").get())?).get(
				"k"
			).get() != YamlValue.StringValue("one two")
		)
	)?
	(items(root.get("c").get())?) | expect_equal([YamlValue.StringValue("p q\nr")])?

test "YAML document start marker accepts same-line content":
	parse(text: "--- a") | expect_ok? | expect_equal(YamlValue.StringValue("a"))?
	(items((parse(text: "--- [1, 2]") | expect_ok?))?).length() | expect_equal(2)?
	parse(text: "--- # note\na: 1") | expect_ok? | expect_equal(
		(parse(text: "a: 1") | expect_ok?)
	)?

test "YAML compact mapping after a sequence marker follows the marker's spacing":
	root := (
		parse(
			text: "-   a: 1\n    b: 2\n-  - x\n   - y\n- c: 3\n  d: 4\n"
		) | expect_ok?
	)
	list := (items(root)?)
	list.length() | expect_equal(3)?

	first := (entries(list.first().get())?)
	first["b"] | expect_equal(YamlValue.NumberValue("2"))?
	(items(list.get(1).clone())?).length() | expect_equal(2)?
	(entries(list.last().get())?)["d"] | expect_equal(YamlValue.NumberValue("4"))?

fn repeated(text: String, count: Int) String:
	if count <= 0: return ""
	if count == 1: return text.clone()

	half := repeated(text: text.clone(), count: count / 2)
	if count % 2 == 1: return half.concat(half).concat(text)

	return half.concat(half)

test "YAML long plain scalars and large mappings parse in linear time":
	long := repeated(text: "x", count: 300000)
	scalar := parse(text: "a: {long}") | expect_ok? | entries?
	scalar["a"] | expect_equal(YamlValue.StringValue(long))?

	var keys = ""
	for index in 0..30000:
		keys = keys.concat("k{index}: 1\n")
	(entries((parse(text: keys) | expect_ok?))?).length() | expect_equal(30000)?

	match parse(text: keys.concat("k7: 2\n")):
		ok(_): return fail("duplicate key after many keys")
		error(_): return

test "YAML flow mapping keys without a colon map to null":
	root := parse(text: "a: \{x, y: 1, z\}\nb: \{\"q\", r: [1]\}") | expect_ok? | entries?
	first := (entries(root.get("a").get())?)
	first.length() | expect_equal(3)?
	first["x"] | expect_equal(YamlValue.Null)?
	first["y"] | expect_equal(YamlValue.NumberValue("1"))?
	first["z"] | expect_equal(YamlValue.Null)?

	second := (entries(root.get("b").get())?)
	second["q"] | expect_equal(YamlValue.Null)?

	match parse(text: "\{x, x\}"):
		ok(_): return fail("duplicate null keys")
		error(_): _ignored := unit

	limited := limits(bytes: none, depth: none, values: 2)

	match parse(text: "\{a, b, c\}", options: limited):
		ok(_): return fail("null keys count against the value limit")
		error(_): _ignored := unit

test "YAML long quoted block and multi-line scalars decode and stringify in linear time":
	long := repeated(text: "x", count: 300000)
	double := parse(text: "a: \"{long}\"") | expect_ok? | entries?
	double["a"] | expect_equal(YamlValue.StringValue(long.clone()))?

	single := parse(text: "a: '{long}'") | expect_ok? | entries?
	single["a"] | expect_equal(YamlValue.StringValue(long.clone()))?

	lines := repeated(text: "word\n  ", count: 20000)
	plain := parse(text: "a: {lines}end") | expect_ok? | entries?
	expect_false(
		(
			plain["a"] != YamlValue.StringValue(
				repeated(text: "word ", count: 20000).concat("end")
			)
		)
	)?

	body := repeated(text: "  line\n", count: 20000)
	literal := parse(text: "a: |\n{body}") | expect_ok? | entries?
	expect_false(
		(
			literal["a"] != YamlValue.StringValue(
				repeated(text: "line\n", count: 20000)
			)
		)
	)?

	root := (parse(text: "a: \"{long}\"") | expect_ok?)
	parse(text: (stringify(value: root) | expect_ok?)) | expect_ok? | expect_equal(root)?

test "YAML block scalar chomping counts every trailing line break":
	(scalar(text: "a: |\n  x\n\n\n\nb: 1", expected: "x\n")?)
	(scalar(text: "a: |-\n  x\n\n\n\nb: 1", expected: "x")?)
	(scalar(text: "a: |+\n  x\n\n\n\nb: 1", expected: "x\n\n\n\n")?)
	(scalar(text: "a: >-\n  x\n\n\n", expected: "x")?)
	(scalar(text: "a: |\n\n\nb: 1", expected: "")?)
	(scalar(text: "a: |+\n\n\nb: 1", expected: "\n\n")?)

test "YAML compact nested sequences resume each level and parse deep chains in linear time":
	small := (
		items(
			(
				parse(
					text: "- - - x\n    - y\n  - z\n- - 1\n  - - 2\n    - 3\n-\n  - -\n    - a: 1\n      b: 2\n"
				) | expect_ok?
			)
		)?
	)
	small.length() | expect_equal(3)?

	first := (items(small.first().get())?)
	first.length() | expect_equal(2)?
	(items(first.first().get())?).length() | expect_equal(2)?
	first.last().get() | expect_equal(YamlValue.StringValue("z"))?

	depth := 3000
	var source = "{repeated(text: "- ", count: depth)}x\n"
	var root = (parse(text: source, options: YamlOptions()) | expect_ok?)

	for level in 1..depth:
		inner := (items(root)?)
		inner.length() | expect_equal(1)?

		next := inner.first().get().clone()
		root = next

	(items(root)?) | expect_equal([YamlValue.StringValue("x")])?

test "YAML stringify escapes C1 control characters so output reparses":
	for code in [127, 128, 133, 150, 159]:
		text := from_scalars([97, code, 98])?
		encoded := stringify(YamlValue.StringValue(text.clone()))?
		expect_equal((parse(encoded)?), YamlValue.StringValue(text))?

test "YAML parse without options stops alias bombs and deep nesting":
	var bomb = "l0: &l0 [x, x, x, x, x, x, x, x, x, x]\n"
	for i in 0..9:
		bomb = bomb + "l{i+1}: &l{i+1} [" + "*l{i}, ".repeat(9).get() + "*l{i}]\n"

	bombed := parse(bomb)
	if bombed.is_ok(): return fail(
		"alias expansion over the default value budget was accepted"
	)

	deep := "[".repeat(20000).get() + "]".repeat(20000).get()
	nested := parse(deep)
	if nested.is_ok(): return fail("nesting over the default depth was accepted")

	lifted := parse(deep, YamlOptions(max_depth: none, max_values: none))
	expect_true(lifted.is_ok())?

test "YAML plain scalars and keys keep Unicode spaces":
	(scalar(text: "a: x\u{a0}\n", expected: "x\u{a0}")?)
	(scalar(text: "a: \u{3000}x\n", expected: "\u{3000}x")?)

	root := parse(text: "k\u{a0}: 1\n") | expect_ok? | entries?
	expect_true(root.contains("k\u{a0}"))?
