// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	YamlValue, parse from "@std/data/yaml.ms",
	StringBuilder from "@std/string_builder.ms",
	expect_equal, expect_error, expect_ok, expect_true, fail from "@std/test/test.ms",
)

// Regressions: block key.

fn invalid_block_key(source: String) Unit!:
	cause := parse(source) | expect_error?
	if cause.kind == "EBADMSG": return ok(unit)

	return fail("expected malformed YAML, got {cause}")

test "YAML unquoted block keys reject reserved leading indicators":
	for key in ["]key", "\}key", ",key", "@key", "`key", "|key", ">key"]:
		invalid_block_key("{key}: value")?
		invalid_block_key("good: value\n{key}: value")?

	invalid_block_key("good: value\n%key: value")?

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

// Regressions: colon.

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

fn invalid_colon(source: String) Unit!:
	cause := parse(source) | expect_error?
	if cause.kind != "EBADMSG": return fail("expected malformed YAML, got {cause}")

	cause.details["reason"] | expect_equal("unexpected mapping colon")?

test "YAML flow scalar rejects a colon before tab":
	invalid_colon("\{a: x:\tb\}")?

test "YAML flow scalar rejects a colon before newline":
	invalid_colon("\{a: x:\nb\}")?

test "YAML flow scalar rejects a colon before a closing mapping":
	invalid_colon("\{a: x:\}")?

test "YAML block scalar rejects an embedded mapping separator":
	invalid_colon("a: x:\tb")?

test "YAML block scalar rejects a trailing mapping separator":
	invalid_colon("a: x:")?

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
	invalid_colon("a: x:\n\n  b")?

// Regressions: comment continuation.

fn rejects_continuation(text: String) Unit!Error:
	cause := parse(text) | expect_error?
	if cause.kind != "EBADMSG": return fail("expected InvalidData, got {cause}")

	return expect_equal(
		cause.details["reason"],
		"unexpected indentation or additional document",
	)

test "YAML inline comments end root and mapping plain scalars":
	rejects_continuation("first # comment\nnext")?
	rejects_continuation("a: first # comment\n  next")?
	rejects_continuation("a: &value first # comment\n  next")?

test "YAML inline comments end later plain continuation lines":
	rejects_continuation("first\nnext # comment\nlast")?
	rejects_continuation("a: first\n  next # comment\n  last")?

test "YAML compact mapping rewrites retain terminating comments":
	rejects_continuation("- key: first # comment\n    next")?
	rejects_continuation("-   key: first # comment\n      next")?
	rejects_continuation("- key: café # comment\n    next")?

test "YAML nested compact sequences retain terminating comments":
	rejects_continuation("- - first # comment\n    next")?
	rejects_continuation("- - - first # comment\n      next")?
	rejects_continuation("- - key: first # comment\n      next")?

test "YAML plain hashes without separation keep folding":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("first#hash next#hash last"))
	(
		parse("a: first#hash\n  next#hash\n  last") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

test "YAML comment-terminated values retain following siblings":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("first"))
	values.add("b", YamlValue.StringValue("second"))
	(
		parse("a: first # comment\nb: second") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)
	(
		parse("- first # comment\n- second") | expect_ok? | expect_equal(
			YamlValue.ArrayValue(
				[
					YamlValue.StringValue("first"),
					YamlValue.StringValue("second"),
				]
			)
		)?
	)

test "YAML compact mapping comments preserve Unicode siblings":
	var values = Map[String, YamlValue]()
	values.add("clé", YamlValue.StringValue("café"))
	values.add("next", YamlValue.StringValue("ok"))
	(
		parse("- clé: café # comment\n  next: ok") | expect_ok? | expect_equal(
			YamlValue.ArrayValue([YamlValue.ObjectValue(values)])
		)?
	)

test "YAML empty values with comments may begin on a later line":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("next"))
	(
		parse("a: # comment\n  next") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)
	(
		parse("- # comment\n  next") | expect_ok? | expect_equal(
			YamlValue.ArrayValue([YamlValue.StringValue("next")])
		)?
	)

test "YAML quoted and flow hashes retain their scalar behavior":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("first # hash next"))
	(
		parse("a: \"first # hash\n  next\"") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)
	(
		parse("[first, # comment\n next]") | expect_ok? | expect_equal(
			YamlValue.ArrayValue(
				[
					YamlValue.StringValue("first"),
					YamlValue.StringValue("next"),
				]
			)
		)?
	)

fn rejects_flow_continuation(text: String, reason: String) Unit!Error:
	cause := parse(text) | expect_error?
	if cause.kind != "EBADMSG": return fail("expected InvalidData, got {cause}")

	return expect_equal(cause.details["reason"], reason)

test "YAML flow sequence comments terminate plain scalar text":
	for source in [
		"[first # comment\n next]", "[\n first # comment\n next]",
		"[first\n # comment\n next]", "[café # comment\n next]",
		"&items [first # comment\n next]", "- - [first # comment\n     next]"
	]:
		rejects_flow_continuation(source, "expected sequence comma")?

test "YAML flow mapping comments terminate plain scalar values":
	for source in ["\{a: first # comment\n next\}", "\{a: first\n # comment\n next\}"]:
		rejects_flow_continuation(source, "expected mapping comma")?

test "YAML flow comments preserve comma and closing boundaries":
	expected := YamlValue.ArrayValue(
		[YamlValue.StringValue("first"), YamlValue.StringValue("next")]
	)
	(parse("[first, # comment\n next]") | expect_ok? | expect_equal(expected)?)
	(parse("[first # comment\n ,next]") | expect_ok? | expect_equal(expected)?)
	(
		parse("[first # comment\n ]") | expect_ok? | expect_equal(
			YamlValue.ArrayValue([YamlValue.StringValue("first")])
		)?
	)

	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("first"))
	values.add("b", YamlValue.StringValue("next"))
	(
		parse("\{a: first # comment\n , b: next\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

test "YAML comments before flow values preserve empty starts":
	(
		parse("[ # comment\n first]")
		| expect_ok?
		| expect_equal(YamlValue.ArrayValue([YamlValue.StringValue("first")]))?
	)

	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("first"))
	(
		parse("\{a: # comment\n first\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

	var empty = Map[String, YamlValue]()
	empty.add("a", YamlValue.Null)
	(
		parse("\{a: # comment\n\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(empty.clone())
		)?
	)
	(
		parse("\{a # comment\n\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(empty.clone())
		)?
	)
	empty.add("b", YamlValue.Null)
	(
		parse("\{a # comment\n , b\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(empty)
		)?
	)

test "YAML flow comment stops follow quoted and alias nodes":
	expected := YamlValue.ArrayValue(
		[
			YamlValue.StringValue("café"),
			YamlValue.StringValue("quoted # hash"),
			YamlValue.StringValue("café"),
			YamlValue.StringValue("last"),
		]
	)
	(
		parse(
			"&items [&a café # first\n, \"quoted # hash\" # second\n, *a # third\n, last]"
		)
		| expect_ok?
		| expect_equal(expected)?
	)

// Regressions: empty entry.

test "YAML flow mappings reject empty comma entries":
	for source in [
		"\{,\}", "\{, key: value\}", "\{key: value,, next: value\}", "[\{,\}]",
		"\{key,,\}"
	]:
		cause := parse(source) | expect_error?
		if cause.kind != "EBADMSG":
			return fail("expected malformed flow entry, got {cause}")

		cause.details["reason"] | expect_equal("expected flow mapping key")?

test "YAML flow mappings retain legal trailing commas":
	var values = Map[String, YamlValue]()
	values.add("key", YamlValue.StringValue("value"))
	(
		parse("\{key: value,\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

	var nulls = Map[String, YamlValue]()
	nulls.add("key", YamlValue.Null)
	(parse("\{key,\}") | expect_ok? | expect_equal(YamlValue.ObjectValue(nulls))?)

test "YAML flow mappings retain existing empty-key forms":
	for source in ["\{\"\": value\}", "\{: value\}"]:
		var values = Map[String, YamlValue]()
		values.add("", YamlValue.StringValue("value"))
		(parse(source) | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?)

// Regressions: error location.

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
	(parse("-\t\tkey: value") | expect_ok? | expect_equal(expected)?)
	(parse("---\n-\t\tkey: value") | expect_ok? | expect_equal(expected)?)
	(
		parse("-\t\t-\t\tkey: value") | expect_ok? | expect_equal(
			YamlValue.ArrayValue([expected.clone()])
		)?
	)

test "YAML block header origins distinguish identical quoted key text":
	error_at("\"|bad\": |bad\n  x", 1, 10)?
	error_at("---\n\"|bad\": |bad\n  x", 2, 10)?

// Regressions: key line.

fn invalid_key_line(source: String) Unit!:
	cause := parse(source) | expect_error?
	if cause.kind != "EBADMSG":
		return fail("expected malformed implicit key, got {cause}")

	(
		cause.details["reason"] | expect_equal(
			"an implicit mapping key must stay on one line"
		)?
	)

test "YAML plain implicit keys cannot span physical lines":
	for source in ["\{key\n next: value\}", "\{key\n: value\}"]:
		invalid_key_line(source)?

test "YAML quoted implicit keys cannot span physical lines":
	for source in [
		"\{'key\n next': value\}", "\{\"key\n next\": value\}",
		"\{\"key\\\n next\": value\}", "\{\"key\"\n: value\}"
	]:
		invalid_key_line(source)?

test "YAML quoted implicit keys may contain escaped newline text":
	var values = Map[String, YamlValue]()
	values.add("key\nnext", YamlValue.StringValue("value"))
	(
		parse("\{\"key\\nnext\": value\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

test "YAML omitted flow values retain multiline node and entry separation":
	for source in ["\{key\n next\}", "\{\"key\n next\"\}"]:
		var values = Map[String, YamlValue]()
		values.add("key next", YamlValue.Null)
		(parse(source) | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?)

	for source in ["\{key\n, next: value\}", "\{\"key\"\n, next: value\}"]:
		var values = Map[String, YamlValue]()
		values.add("key", YamlValue.Null)
		values.add("next", YamlValue.StringValue("value"))
		(parse(source) | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?)

test "YAML flow values can begin on the line after their colon":
	var values = Map[String, YamlValue]()
	values.add("key", YamlValue.StringValue("value"))
	(
		parse("\{key:\n value\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

// Regressions: node scan.

test "YAML quotes inside a plain scalar do not hide comments":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("plain 'x"))
	(
		parse("a: plain 'x # comment") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

test "YAML plain scalar comments end the document node":
	(
		parse("x 'y # comment")
		| expect_ok?
		| expect_equal(YamlValue.StringValue("x 'y"))?
	)

test "YAML plain flow quotes do not absorb later mapping members":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.ArrayValue([YamlValue.StringValue("plain 'x")]))
	values.add("next", YamlValue.StringValue("value"))
	(
		parse(
			"a: [plain 'x # comment\n]\nnext: value"
		) | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?
	)

test "YAML whole-line flow comments are separation":
	(
		parse("[\n# note\n1\n]")
		| expect_ok?
		| expect_equal(YamlValue.ArrayValue([YamlValue.NumberValue("1")]))?
	)

test "YAML quoted nodes retain comment markers with adjacent values":
	var values = Map[String, YamlValue]()
	values.add("key", YamlValue.StringValue("hash # kept"))
	(
		parse("\{\"key\":\"hash # kept\"\}") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

test "YAML anchor properties preserve quoted comment markers":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("hash # kept"))
	values.add("b", YamlValue.StringValue("hash # kept"))
	(
		parse(
			"a: &message \"hash # kept\"\nb: *message"
		) | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?
	)

test "YAML comment contents do not open quotes or containers":
	var values = Map[String, YamlValue]()
	values.add(
		"a",
		YamlValue.ArrayValue(
			[YamlValue.NumberValue("1"), YamlValue.NumberValue("2")]
		),
	)
	values.add("next", YamlValue.StringValue("value"))
	(
		parse(
			"a: [1, # '\"[\{ unmatched\n 2]\nnext: value"
		) | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?
	)

test "YAML Unicode spaces do not start quoted syntax":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("\u{a0}'text"))
	(
		parse("a: \u{a0}'text # comment") | expect_ok? | expect_equal(
			YamlValue.ObjectValue(values)
		)?
	)

test "YAML brackets inside block plain text stay ordinary characters":
	var values = Map[String, YamlValue]()
	values.add("a", YamlValue.StringValue("word [literal"))
	values.add("next", YamlValue.StringValue("value"))
	(
		parse(
			"a: word [literal # comment\nnext: value"
		) | expect_ok? | expect_equal(YamlValue.ObjectValue(values))?
	)

test "YAML plain closing brackets do not hide malformed nested values":
	cause := parse("word] [text]: \{value: 1\}\}") | expect_error?
	cause.kind | expect_equal("EBADMSG")?

// Regressions: incremental flow.

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

// Regressions: block indentation.

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
		),
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

// Regressions: document boundaries.

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
		(parse("--- \"value: word\"\n")?),
		YamlValue.StringValue("value: word"),
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
			YamlValue.ArrayValue([YamlValue.StringValue(marker.clone())]),
		)?
		for quote in ["'", "\""]:
			expect_equal(
				(parse("{quote}word\n {marker}\n end{quote}")?),
				YamlValue.StringValue("word {marker} end"),
			)?
		for suffix in ["word", "#literal", "\u{a0}word"]:
			expect_equal(
				(parse("[\n{marker}{suffix}\n]")?),
				YamlValue.ArrayValue(
					[YamlValue.StringValue("{marker}{suffix}")]
				),
			)?
		expect_equal(
			(parse("[\n{marker}]")?),
			YamlValue.ArrayValue([YamlValue.StringValue(marker.clone())]),
		)?
