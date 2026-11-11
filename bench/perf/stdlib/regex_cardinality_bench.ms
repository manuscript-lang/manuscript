import (
	compile from "@std/string.ms",
	keep, measure from "@std/test/bench.ms",
	expect_equal from "@std/test/test.ms",
)

fn rows_bench(count: Int, grouped: Bool) Result[Unit, Error]:
	pattern := if grouped: "(word)([0-9]+)" else: "word[0-9]+"
	re := try compile(pattern)
	text := try "word123 ".repeat(count)
	expected := if grouped: ["word123", "word", "123"] else: ["word123"]
	width := if grouped: 14 else: 7

	fn work() Result[Unit, Error]:
		rows := try re.captures_all(text)
		try expect_equal(rows.length(), count)

		var checksum = 0

		for row in rows:
			try expect_equal(row, expected)
			for group in row:
				checksum += group.length()

		try expect_equal(checksum, count * width)
		return keep(checksum)

	return measure(1, work)

bench "regex.cardinality.whole.0":
	try rows_bench(0, false)

bench "regex.cardinality.whole.1":
	try rows_bench(1, false)

bench "regex.cardinality.whole.128":
	try rows_bench(128, false)

bench "regex.cardinality.whole.2000":
	try rows_bench(2000, false)

bench "regex.cardinality.grouped.1":
	try rows_bench(1, true)

bench "regex.cardinality.grouped.2000":
	try rows_bench(2000, true)

bench "regex.cardinality.whole.long":
	re := try compile("a+")
	text := try "a".repeat(65536)
	expected := [[text.clone()]]

	fn work() Result[Unit, Error]:
		rows := try re.captures_all(text, 1)
		try expect_equal(rows, expected)
		return keep(rows[0][0].length())

	try measure(1, work)

bench "regex.cardinality.whole.empty_matches":
	re := try compile("a*")

	fn work() Result[Unit, Error]:
		rows := try re.captures_all("a🙂🙂a", 3)
		try expect_equal(rows, [["a"], [""], ["a"]])
		return keep(rows.length())

	try measure(1, work)

bench "regex.cardinality.whole.over_limit":
	re := try compile("word[0-9]+")
	text := try "word123 ".repeat(2000)

	fn work() Result[Unit, Error]:
		out := re.captures_all(text, 1)
		expected: Result[List[List[String]], Error] := error(
			Error("regular expression: limit exceeded", kind: "EOVERFLOW")
		)
		try expect_equal(out, expected)
		return keep(if out.is_error(): 1 else: 0)

	try measure(1, work)

fn first_bench(grouped: Bool, found: Bool) Result[Unit, Error]:
	re := try compile(if grouped: "(word)([0-9]+)" else: "word[0-9]+")
	text := if found: "word123" else: "none"
	hit := if grouped: ["word123", "word", "123"] else: ["word123"]
	expected := if found: hit else: []

	fn work() Result[Unit, Error]:
		out := re.captures(text)
		try expect_equal(out, expected)
		return keep(out.length())

	return measure(1, work)

bench "regex.cardinality.first.whole.hit":
	try first_bench(false, true)

bench "regex.cardinality.first.whole.miss":
	try first_bench(false, false)

bench "regex.cardinality.first.grouped.hit":
	try first_bench(true, true)

bench "regex.cardinality.first.whole.long":
	re := try compile("a+")
	text := try "a".repeat(65536)
	expected := [text.clone()]

	fn work() Result[Unit, Error]:
		out := re.captures(text)
		try expect_equal(out, expected)
		return keep(out[0].length())

	try measure(1, work)

fn names_bench(named: Bool, long_miss: Bool) Result[Unit, Error]:
	re := try compile(if named: "word(?P<id>[0-9]+)" else: "word[0-9]+")
	text := if long_miss: (try "z".repeat(65536)) else: "word123"
	var expected = Map[String, String]()
	if named and not long_miss:
		expected.add("id", "123")

	fn work() Result[Unit, Error]:
		out := re.named_captures(text)
		try expect_equal(out, expected)
		return keep(out.length())

	return measure(1, work)

bench "regex.cardinality.named.whole.hit":
	try names_bench(false, false)

bench "regex.cardinality.named.whole.long_miss":
	try names_bench(false, true)

bench "regex.cardinality.named.named.hit":
	try names_bench(true, false)

fn anonymous_names_bench(long_miss: Bool) Result[Unit, Error]:
	re := try compile("(word)([0-9]+)")
	text := if long_miss: (try "z".repeat(65536)) else: "word123"
	expected := Map[String, String]()

	fn work() Result[Unit, Error]:
		out := re.named_captures(text)
		try expect_equal(out, expected)
		return keep(out.length())

	return measure(1, work)

bench "regex.cardinality.named.anonymous.hit":
	try anonymous_names_bench(false)

bench "regex.cardinality.named.anonymous.long_miss":
	try anonymous_names_bench(true)

fn late_names_bench(found: Bool) Result[Unit, Error]:
	prefix := try "(a?)".repeat(128)
	re := try compile(prefix + "(?P<last>x)")
	text := if found: "x" else: "z"
	var expected = Map[String, String]()
	if found:
		expected.add("last", "x")

	fn work() Result[Unit, Error]:
		out := re.named_captures(text)
		try expect_equal(out, expected)
		return keep(out.length())

	return measure(1, work)

bench "regex.cardinality.named.late.hit":
	try late_names_bench(true)

bench "regex.cardinality.named.late.miss":
	try late_names_bench(false)
