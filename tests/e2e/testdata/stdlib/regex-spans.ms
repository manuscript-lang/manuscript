import (
	RegexSpan, compile from "@std/string.ms",
	expect_equal,
	expect_error,
	expect_none,
	expect_ok,
	expect_some from "@std/test/test.ms",
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
	unicode := compile("é|🙂") | expect_ok?
	unicode.find_all_spans("aé🙂") | expect_ok? | pairs | expect_equal([[1, 3], [3, 7]])?

	empty := compile("") | expect_ok?
	empty.find_all_spans(
		"é🙂"
	) | expect_ok? | pairs | expect_equal([[0, 0], [2, 2], [6, 6]])?

	adjacent := compile("a*") | expect_ok?
	adjacent.find_all_spans(
		"a🙂🙂a"
	) | expect_ok? | pairs | expect_equal([[0, 1], [5, 5], [9, 10]])?

	no_match := compile("x") | expect_ok?
	no_match.find_all_spans("é🙂", 0) | expect_ok? | pairs | expect_equal(
		List[List[Int]]()
	)?

test "capture spans distinguish no match absent groups and empty captures":
	re := compile("(a)?()") | expect_ok?
	first := re.capture_spans("") | expect_ok? | expect_some?
	expected: List[List[Int]?] := [[0, 0], none, [0, 0]]
	first | slots | expect_equal(expected)?

	absent := compile("(x)") | expect_ok?
	absent.capture_spans("abc", 0) | expect_ok? | expect_none?
	re.captures("") | expect_equal(["", "", ""])?

	plain := compile("é") | expect_ok?
	plain_expected: List[List[Int]?] := [[1, 3]]
	plain.capture_spans(
		"aé", 1
	) | expect_ok? | expect_some? | slots | expect_equal(plain_expected)?
	plain.capture_spans(
		"aé", 0
	) | expect_error? | expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)?

test "capture rows clear absent groups and retain all group indices":
	re := compile("(?P<left>é)|(🙂)") | expect_ok?
	rows := re.capture_all_spans("é🙂é", 3, 9) | expect_ok?
	rows.length() | expect_equal(3)?

	left: List[List[Int]?] := [[0, 2], [0, 2], none]
	right: List[List[Int]?] := [[2, 6], none, [2, 6]]
	rows[0] | slots | expect_equal(left)?
	rows[1] | slots | expect_equal(right)?

	last: List[List[Int]?] := [[6, 8], [6, 8], none]
	rows[2] | slots | expect_equal(last)?

	bytes := "é🙂é".to_bytes()
	present := rows[1][2].clone() | expect_some?
	bytes.decode_utf8_range(
		present.start, present.end
	) | expect_some? | expect_equal("🙂")?

test "span budgets cover whole and unmatched capture slots":
	re := compile("(a)|(b)") | expect_ok?
	re.find_all_spans("ab", 2) | expect_ok? | pairs | expect_equal([[0, 1], [1, 2]])?
	re.find_all_spans(
		"ab", 1
	) | expect_error? | expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)?
	re.capture_spans(
		"ab", 3
	) | expect_ok? | expect_some? | slots | expect_equal([[0, 1], [0, 1], none])?
	re.capture_spans(
		"ab", 2
	) | expect_error? | expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)?

	exact := re.capture_all_spans("ab", 2, 6) | expect_ok?
	exact.length() | expect_equal(2)?
	re.capture_all_spans(
		"ab", 2, 5
	) | expect_error? | expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)?
	re.capture_all_spans(
		"ab", 1, 6
	) | expect_error? | expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)?
	re.capture_all_spans("", 0, 0) | expect_ok? | expect_equal(List[List[RegexSpan?]]())?

	for cap in [-1, -9223372036854775808]:
		re.find_all_spans(
			"", cap
		) | expect_error? | expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)?
		re.capture_spans(
			"", cap
		) | expect_error? | expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)?
		re.capture_all_spans(
			"", cap, none
		) | expect_error? | expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)?
		re.capture_all_spans(
			"", none, cap
		) | expect_error? | expect_equal(
			Error("regular expression: invalid input", kind: "EINVAL")
		)?

test "span methods support bound calls and preserve anchor context":
	re := compile("(?m)(^a)|(b$)") | expect_ok?
	find := re.find_all_spans
	find("za b\na b", none) | expect_ok? | pairs | expect_equal(
		[[3, 4], [5, 6], [7, 8]]
	)?

	captures := re.capture_spans
	captures("za b\na b", none) | expect_ok? | expect_some? | slots | expect_equal(
		[[3, 4], none, [3, 4]]
	)?

	all := re.capture_all_spans
	rows := all("za b\na b", none, none) | expect_ok?
	rows.length() | expect_equal(3)?

test "span results remain bounded for dense matches":
	text := "é🙂".repeat(32768) | expect_ok?
	re := compile("(é)|(🙂)") | expect_ok?
	re.find_all_spans(
		text, 1
	) | expect_error? | expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)?
	re.capture_all_spans(
		text, none, 3
	) | expect_error? | expect_equal(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)?
	re.capture_spans(
		text, 3
	) | expect_ok? | expect_some? | slots | expect_equal([[0, 2], [0, 2], none])?
