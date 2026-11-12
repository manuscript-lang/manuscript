// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	compile from "@std/regex.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

test "regex receivers execute matching replacement and empty results":
	regex := compile("[0-9]+")?
	expect_false(not regex.matches("a12b"))?
	expect_false(regex.matches("abc"))?
	expect_equal((regex.find_all("a12b3")?), ["12", "3"])?
	expect_false(not (regex.find_all("abc", 0)?).is_empty())?
	expect_equal((regex.replace_all("a12b3", "#")?), "a#b#")?

test "regex rejects invalid expressions and exhausted budgets":
	invalid := compile("[")
	expect_false(not invalid.is_error())?
	expect_equal(invalid.err().kind, "EBADMSG")?
	expect_equal(
		invalid.err().message,
		"regular expression: invalid data: unclosed character class at column 1",
	)?

	regex := compile("[0-9]+")?
	limited: List[String]! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(regex.find_all("1 2", 1), limited)?

	output_limit: String! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(regex.replace_all("1", "long", 3), output_limit)?

test "regex captures groups spans and splits":
	date := compile("(?P<y>[0-9]\{4\})-(?P<m>[0-9]\{2\})")?
	expect_equal(date.captures("on 2026-10 ok"), ["2026-10", "2026", "10"])?
	expect_equal(date.captures("none"), [])?
	expect_equal(date.named_captures("2026-10")["y"], "2026")?
	expect_equal(date.named_captures("none").is_empty(), true)?
	expect_equal(date.find_span("on 2026-10").get(), [3, 10])?
	expect_equal(date.find_span("none").is_none(), true)?
	expect_equal(
		(date.captures_all("2026-10 2027-11")?),
		[["2026-10", "2026", "10"], ["2027-11", "2027", "11"]],
	)?

	comma := compile(",\\s*")?
	expect_equal((comma.split("a, b,c")?), ["a", "b", "c"])?
	expect_equal((comma.split("")?), [""])?

	swap := compile("(\\w+)@(?P<host>\\w+)")?
	expect_equal(
		(swap.replace_template("me@home x@y", "$\{host\}:$1 $$")?),
		"home:me $ y:x $",
	)?

	limited: List[String]! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(comma.split("a,b,c", 2), limited)?

test "regex repeated captures clear absent groups and preserve budgets":
	re := compile("(a)|(b+)")?
	expect_equal(
		(re.captures_all("a bbb a", 3)?),
		[["a", "a", ""], ["bbb", "", "bbb"], ["a", "a", ""]],
	)?

	limited: List[List[String]]! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(re.captures_all("a bbb a", 2), limited)?
	expect_equal((re.captures_all("xyz", 0)?), [])?

test "regex repeated template expansion preserves byte budgets":
	re := compile("(?P<a>a+)|(b+)")?
	expect_equal(
		(re.replace_template("aaaaaaaa b a", "$\{a\}:$\{2\}$$", 18)?),
		"aaaaaaaa:$ :b$ a:$",
	)?
	expect_equal((re.replace_template("a b", "$$", 3)?), "$ $")?

	limited: String! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(re.replace_template("a b", "$$", 2), limited)?
	expect_equal((re.replace_template("a b", "xy", 5)?), "xy xy")?
	expect_equal(re.replace_template("a b", "xy", 4), limited)?

test "regex capped templates preserve Unicode references and malformed syntax":
	re := compile("(?P<word>é)(?P<名字>🙂)(x)?")?
	template := "$\{名字\}:$\{+1\}:$$:$3"
	expect_equal((re.replace_template("é🙂", template, 10)?), "🙂:é:$:")?
	expect_equal((re.replace_template("é🙂", "$3$\{missing\}", 0)?), "")?
	expect_equal((re.replace_template("é🙂", "$\{open $1", 9)?), "$\{open é")?

	limited: String! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(re.replace_template("é🙂", template, 9), limited)?

	text := "é".repeat(65536)?
	repeated := "$0".repeat(128)?
	whole := compile(".+")?
	expect_equal(whole.replace_template(text, repeated, 0), limited)?

test "regex named captures preserve unnamed gaps and absent groups":
	re := compile("(a)?(?P<first>b)?(c)(?P<empty>d*)(?P<last>e)")?
	found := re.named_captures("ce")
	expect_equal(found.length(), 2)?
	expect_equal(found.get("first").is_none(), true)?
	expect_equal(found.get("empty").get(), "")?
	expect_equal(found.get("last").get(), "e")?

test "regex capture methods preserve whole match only patterns":
	re := compile("\\bword\\b")?
	expect_equal(re.captures("sword word"), ["word"])?
	expect_equal(re.captures("sword"), [])?
	expect_equal(re.named_captures("word").is_empty(), true)?

	unnamed := compile("(word)([0-9]+)")?
	expect_equal(unnamed.named_captures("word123").is_empty(), true)?
	expect_equal((re.captures_all("sword word word", 2)?), [["word"], ["word"]])?

	limited: List[List[String]]! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(re.captures_all("word word", 1), limited)?
	expect_equal((re.captures_all("sword", 0)?), [])?

	empty := compile("a*")?
	expect_equal((empty.captures_all("a🙂🙂a", 3)?), [["a"], [""], ["a"]])?

	absent := compile("(a)?b")?
	expect_equal(absent.captures("b"), ["b", ""])?
	expect_equal((absent.captures_all("b b")?), [["b", ""], ["b", ""]])?

test "regex collection budgets preserve empty adjacency and exact counts":
	re := compile("a*")?
	expect_equal((re.find_all("a🙂🙂a", 3)?), ["a", "", "a"])?
	expect_equal((re.captures_all("a🙂🙂a", 3)?), [["a"], [""], ["a"]])?

	find_limit: List[String]! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	capture_limit: List[List[String]]! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(re.find_all("a🙂🙂a", 2), find_limit)?
	expect_equal(re.captures_all("a🙂🙂a", 2), capture_limit)?
	expect_equal(re.find_all("", 0), find_limit)?
	expect_equal(re.captures_all("", 0), capture_limit)?

	for pattern in ["x", "(x)"]:
		matching := compile(pattern)?
		expect_equal((matching.find_all("none", 0)?), [])?
		expect_equal((matching.captures_all("none", 0)?), [])?
		expect_equal((matching.find_all("é🙂", 0)?), [])?
		expect_equal((matching.captures_all("é🙂", 0)?), [])?
		expect_equal(matching.find_all("x", 0), find_limit)?
		expect_equal(matching.captures_all("x", 0), capture_limit)?

		for max in [1, 4, 8]:
			text := "x".repeat(max)?
			expect_equal((matching.find_all(text, max)?).length(), max)?
			expect_equal((matching.captures_all(text, max)?).length(), max)?
			expect_equal(matching.find_all(text + "x", max), find_limit)?
			expect_equal(matching.captures_all(text + "x", max), capture_limit)?

test "regex compile errors preserve columns after anchors and numbered lines":
	for item in [
		["^(", "unclosed group at column 2"],
		["^ (", "unclosed group at column 3"],
		["é🙂(", "unclosed group at column 3"],
		["a\n(", "unclosed group at column 1"],
		["(?x)\n^(", "unclosed group at column 2"],
	]:
		invalid := compile(item[0])
		expect_equal(invalid.err().kind, "EBADMSG")?
		expect_equal(
			invalid.err().message,
			"regular expression: invalid data: " + item[1],
		)?

test "regex compile errors point to duplicate flags and group names":
	for item in [
		["(?ii)", "duplicate flag at column 4"],
		["(?i-i)", "duplicate flag at column 5"],
		["(?-i-m)", "flag negation operator repeated at column 5"],
		["(?P<word>a)(?P<word>b)", "duplicate capture group name at column 16"],
		["(?P<名字>a)\n  (?P<名字>b)", "duplicate capture group name at column 7"],
		["a\n(?ii)", "duplicate flag at column 4"],
		["a\n(?-i-m)", "flag negation operator repeated at column 5"],
	]:
		invalid := compile(item[0])
		expect_equal(invalid.err().kind, "EBADMSG")?
		expect_equal(
			invalid.err().message,
			"regular expression: invalid data: " + item[1],
		)?
