import (
	compile, RegexSpan from "@std/string.ms",
	expect_equal,
	expect_ok,
	expect_error,
	expect_some,
	expect_none from "@std/test/test.ms",
)

fn pairs(spans: List[RegexSpan]) List[List[Int]]:
	var out = List[List[Int]](reserve: spans.length())
	for span in spans: out.append([span.start, span.end])
	return out

fn slots(spans: List[RegexSpan?]) List[List[Int]?]:
	var out = List[List[Int]?](reserve: spans.length())

	for span in spans:
		if present := span:
			out.append([present.start, present.end])
		else:
			out.append(none)

	return out

test "match spans use UTF8 byte offsets and existing empty adjacency":
	unicode := compile("é|🙂") | try expect_ok
	unicode.find_all_spans(
		"aé🙂"
	) | try expect_ok | pairs | try expect_equal([[1, 3], [3, 7]])

	empty := compile("") | try expect_ok
	empty.find_all_spans(
		"é🙂"
	) | try expect_ok | pairs | try expect_equal([[0, 0], [2, 2], [6, 6]])

	adjacent := compile("a*") | try expect_ok
	adjacent.find_all_spans(
		"a🙂🙂a"
	) | try expect_ok | pairs | try expect_equal([[0, 1], [5, 5], [9, 10]])

	no_match := compile("x") | try expect_ok
	no_match.find_all_spans("é🙂", 0) | try expect_ok | pairs | try expect_equal(
		List[List[Int]]()
	)

test "capture spans distinguish no match absent groups and empty captures":
	re := compile("(a)?()") | try expect_ok
	first := re.capture_spans("") | try expect_ok | try expect_some
	expected: List[List[Int]?] := [[0, 0], none, [0, 0]]
	first | slots | try expect_equal(expected)

	absent := compile("(x)") | try expect_ok
	absent.capture_spans("abc", 0) | try expect_ok | try expect_none
	re.captures("") | try expect_equal(["", "", ""])

	plain := compile("é") | try expect_ok
	plain_expected: List[List[Int]?] := [[1, 3]]
	plain.capture_spans(
		"aé", 1
	) | try expect_ok | try expect_some | slots | try expect_equal(plain_expected)
	plain.capture_spans(
		"aé", 0
	) | try expect_error | try expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)

test "capture rows clear absent groups and retain all group indices":
	re := compile("(?P<left>é)|(🙂)") | try expect_ok
	rows := re.capture_all_spans("é🙂é", 3, 9) | try expect_ok
	rows.length() | try expect_equal(3)

	left: List[List[Int]?] := [[0, 2], [0, 2], none]
	right: List[List[Int]?] := [[2, 6], none, [2, 6]]
	rows[0] | slots | try expect_equal(left)
	rows[1] | slots | try expect_equal(right)

	last: List[List[Int]?] := [[6, 8], [6, 8], none]
	rows[2] | slots | try expect_equal(last)

	bytes := "é🙂é".to_bytes()
	present := rows[1][2].clone() | try expect_some
	bytes.decode_utf8_range(
		present.start, present.end
	) | try expect_some | try expect_equal("🙂")

test "span budgets cover whole and unmatched capture slots":
	re := compile("(a)|(b)") | try expect_ok
	re.find_all_spans(
		"ab", 2
	) | try expect_ok | pairs | try expect_equal([[0, 1], [1, 2]])
	re.find_all_spans(
		"ab", 1
	) | try expect_error | try expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	re.capture_spans(
		"ab", 3
	) | try expect_ok | try expect_some | slots | try expect_equal(
		[[0, 1], [0, 1], none]
	)
	re.capture_spans(
		"ab", 2
	) | try expect_error | try expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)

	exact := re.capture_all_spans("ab", 2, 6) | try expect_ok
	exact.length() | try expect_equal(2)
	re.capture_all_spans(
		"ab", 2, 5
	) | try expect_error | try expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	re.capture_all_spans(
		"ab", 1, 6
	) | try expect_error | try expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	re.capture_all_spans("", 0, 0) | try expect_ok | try expect_equal(
		List[List[RegexSpan?]]()
	)

	for cap in [-1, -9223372036854775808]:
		re.find_all_spans(
			"", cap
		) | try expect_error | try expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)
		re.capture_spans(
			"", cap
		) | try expect_error | try expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)
		re.capture_all_spans(
			"", cap, none
		) | try expect_error | try expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)
		re.capture_all_spans(
			"", none, cap
		) | try expect_error | try expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)

test "span methods support bound calls and preserve anchor context":
	re := compile("(?m)(^a)|(b$)") | try expect_ok
	find := re.find_all_spans
	find("za b\na b", none) | try expect_ok | pairs | try expect_equal(
		[[3, 4], [5, 6], [7, 8]]
	)

	captures := re.capture_spans
	captures("za b\na b", none) | try expect_ok | try expect_some | slots | try expect_equal(
		[[3, 4], none, [3, 4]]
	)

	all := re.capture_all_spans
	rows := all("za b\na b", none, none) | try expect_ok
	rows.length() | try expect_equal(3)

test "span results remain bounded for dense matches":
	text := "é🙂".repeat(32768) | try expect_ok
	re := compile("(é)|(🙂)") | try expect_ok
	re.find_all_spans(
		text, 1
	) | try expect_error | try expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	re.capture_all_spans(
		text, none, 3
	) | try expect_error | try expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	re.capture_spans(
		text, 3
	) | try expect_ok | try expect_some | slots | try expect_equal(
		[[0, 2], [0, 2], none]
	)
