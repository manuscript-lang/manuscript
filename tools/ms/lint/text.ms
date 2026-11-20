// The lexical rules: trailing whitespace (MSL001), a missing final newline (MSL002) and
// a `//` that reads like floor division (MSL133). They read the source and its tokens
// and nothing else.
import (
	expect_equal from "@std/test/test.ms",

	Token, lex, token_kind from "../syntax.ms",
	Finding, finding from "./finding.ms",
)

fn is_digit(byte: UInt8) Bool: byte >= 48 and byte <= 57

fn is_alpha(byte: UInt8) Bool: (
	(byte >= 65 and byte <= 90)
	or (byte >= 97 and byte <= 122)
)

// Whether the `//` at byte `slash` of `line` ends an expression and holds only a
// number:
// `mid := (lo + hi) // 2`, a Python floor division that compiles as `(lo + hi)`.
export fn floor_division_shape(line: String, slash: Int) Bool:
	before := line.view(0, slash).trim_end()
	before_bytes := before.as_bytes()
	if before_bytes.length() == 0: return false

	last := before_bytes[before_bytes.length() - 1]
	operand_end := (
		is_digit(last)
		or is_alpha(last)
		or last == 41
		or last == 93
		or last == 95
	)
	comment := line.view(slash + 2, line.length()).trim().trim_end_chars(")]")
	comment_bytes := comment.as_bytes()
	if not operand_end or comment_bytes.length() == 0 or not is_digit(comment_bytes[0]): return false

	for i in 0..comment_bytes.length():
		byte := comment_bytes[i]
		if not is_digit(byte) and byte != 46: return false

	// `total := 1 + 2 * 3 // 7` annotates a result: the expression is all literals.
	var start = 0
	for i in 0..before_bytes.length():
		if before_bytes[i] == 61 or before_bytes[i] == 58: start = i + 1
	for i in start..before_bytes.length():
		if is_alpha(before_bytes[i]) or before_bytes[i] == 95: return true
	return false

// Whether byte `at` is outside any text literal, by the token ranges `strings` (start,
// end pairs in source order, original offsets).
fn outside_text(strings: List[Int], at: Int) Bool:
	// First string whose end is past `at`; it covers `at` when it starts at or before
	// it.
	var low = 0
	var high = strings.length() / 2

	while low < high:
		mid := (low + high) / 2

		if strings[mid * 2 + 1] <= at: low = mid + 1
		else: high = mid

	if low >= strings.length() / 2: return true

	return strings[low * 2] > at

fn string_ranges(tokens: List[Token]) List[Int]:
	string_kind := token_kind("STRING")
	var ranges = List[Int]()

	for token in tokens:
		if token.kind == string_kind:
			ranges.append(token.offset)
			ranges.append(token.end_offset)

	return ranges

// Lexical findings for `source`, in the order the Rust rule reported them. An unlexable
// file has no text boundaries, so it yields no whitespace or floor-division finding: a
// quick fix there could change the inside of a text literal.
export fn lint_source(file: String, source: String) List[Finding]:
	var findings = List[Finding]()
	var strings = List[Int]()
	var lexable = false

	match lex(source):
		ok(tokens):
			strings = string_ranges(tokens)
			lexable = true
		error(_failure): void

	var offset = 0
	var line = 0

	for text in source.split_after("\n"):
		line += 1

		body := text.cut_suffix("\n").get_or(text)
		body_text := body.cut_suffix("\r").get_or(body)
		trimmed := body_text.trim_end_chars(" \t")
		at := offset + trimmed.length()
		if (
			trimmed.length() != body_text.length()
			and lexable
			and outside_text(strings, at)
		):
			findings.append(
				finding(
					"MSL001",
					"warning",
					"Remove trailing whitespace",
					file,
					at,
					line,
					trimmed.length() + 1,
				)
			)
		if slash := body_text.index_of("//"):
			if (
				floor_division_shape(body_text, slash)
				and lexable
				and outside_text(strings, offset + slash)
			):
				findings.append(
					finding(
						"MSL133",
						"warning",
						"`//` starts a comment, so everything after it is ignored; Int `/` already truncates, so write `a / 2` for a floor division",
						file,
						offset + slash,
						line,
						slash + 1,
					)
				)
		offset += text.length()

	if source.length() > 0 and not source.ends_with("\n"):
		newlines := source.count("\n")
		var column = source.length() + 1
		if last := source.last_index_of("\n"): column = source.length() - last
		findings.append(
			finding(
				"MSL002",
				"warning",
				"End the file with a newline",
				file,
				source.length(),
				newlines + 1,
				column,
			)
		)

	return findings

fn codes(source: String) List[String]:
	var out = List[String]()
	for finding in lint_source("a.ms", source): out.append(
		f"{finding.code}@{finding.line}:{finding.column}"
	)
	return out

test "trailing whitespace is reported at its first byte":
	expect_equal(codes("fn main() Void:  \n\tvoid\n"), ["MSL001@1:16"])?

test "a missing final newline is reported after the last byte":
	expect_equal(codes("fn main() Void:\n\tvoid"), ["MSL002@2:6"])?

test "a floor-division comment is reported at the slashes":
	expect_equal(codes("fn f(a: Int) Int:\n\treturn (a + 1) // 2\n"), ["MSL133@2:17"])?

test "a comment that annotates an all-literal expression is not floor division":
	expect_equal(codes("total := 1 + 2 * 3 // 7\n"), [])?

test "trailing spaces inside a text literal are not reported":
	expect_equal(codes("x := \"\"\"\n  a  \n  \"\"\"\n"), [])?

test "an unlexable file reports nothing about whitespace":
	expect_equal(codes("x := \"unterminated  \n"), [])?
