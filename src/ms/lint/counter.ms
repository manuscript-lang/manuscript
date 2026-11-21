// A counter loop written as a `while` (MSL122): `var i = 0`, `while i < n:` and a final
// `i += 1` is `for i in 0..n:`. The rewrite changes the text of three places, so it is
// offered only when the counter is not otherwise used, the bound cannot change inside
// the loop, and the pieces sit alone on their lines.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Analyzed, analyze from "./analysis.ms",
	Finding, finding, with_fix from "./finding.ms",
	first_offset, last_offset from "./spans.ms",
	changed_in, mentions, spelling from "./uses.ms",
)

// The binary operator numbers of `<` and `+`.
OP_LESS := 4
OP_ADD := 8
// A compound assignment keeps the operator in the flags above this factor.
COMPOUND := 2
OPERATOR_SHIFT := 256

type Scan:
	tree: Syntax
	source: Bytes
	file: String
	facts: Analyzed?

fn text(s: Scan, from: Int, to: Int) String:
	if from < 0 or to > s.source.length() or from > to: return ""
	return s.source.view(from, to).decode_utf8().get_or("")

// Whether the bytes `from..to` are only spaces, tabs and carriage returns.
fn blank(s: Scan, from: Int, to: Int) Bool:
	for at in from..to:
		byte := s.source[at]
		if byte != 32 and byte != 9 and byte != 13: return false

	return true

// The offset of the first byte of the line holding `offset`.
fn line_start(s: Scan, offset: Int) Int:
	var at = offset
	while at > 0 and s.source[at - 1] != 10: at -= 1
	return at

// The offset of the next newline at or after `offset`, the end of the text when none.
fn line_end(s: Scan, offset: Int) Int:
	var at = offset
	while at < s.source.length() and s.source[at] != 10: at += 1
	return at

fn is_name(s: Scan, at: Int) Bool:
	return s.tree.kind[at] == node_kind("Name")

fn written(s: Scan, at: Int) String:
	return text(s, first_offset(s.tree, at), last_offset(s.tree, at))

fn plain_number(s: Scan, at: Int) Bool:
	if s.tree.kind[at] != node_kind("Number"): return false

	digits := written(s, at).as_bytes()
	for index in 0..digits.length():
		if digits[index] < 48 or digits[index] > 57: return false
	return not digits.is_empty()

// Whether any statement of `statements` mentions or may write `name`.
fn used(s: Scan, statements: List[Int], name: String) Bool:
	for at in statements:
		if mentions(s.tree, at, name) > 0 or changed_in(s.tree, at, name, s.facts): return true
	return false

fn wrote(s: Scan, statements: List[Int], name: String) Bool:
	return statements.any(fn at: changed_in(s.tree, at, name, s.facts))

// Whether `step` is `name += 1` or `name = name + 1`; the syntax table writes the first
// as the second, with the operator in the assignment's flags.
fn counts_up(s: Scan, step: Int, name: String) Bool:
	if s.tree.kind[step] != node_kind("Assign") or spelling(s.tree, step) != name: return false

	flags := s.tree.flags[step]
	if flags != 0 and flags != COMPOUND + OP_ADD * OPERATOR_SHIFT: return false

	value := children(s.tree, step)[1]
	if s.tree.kind[value] != node_kind("Binary") or s.tree.flags[value] != OP_ADD: return false

	parts := children(s.tree, value)
	if not is_name(s, parts[0]) or spelling(s.tree, parts[0]) != name: return false

	return written(s, parts[1]) == "1"

// The index of the last statement before `at` that binds `name`.
fn binding_of(s: Scan, statements: List[Int], at: Int, name: String) Int?:
	var found = at

	while found > 0:
		found -= 1

		candidate := statements[found]
		if s.tree.kind[candidate] != node_kind("Bind"): continue

		pattern := children(s.tree, candidate)[0]
		if (
			s.tree.kind[pattern] == node_kind("PatName")
			and spelling(s.tree, pattern) == name
		): return found

	return none

fn counter_while(s: Scan, statements: List[Int], at: Int, var out: List[Finding]) Void:
	loop := statements[at]
	if s.tree.kind[loop] != node_kind("While"): return

	parts := children(s.tree, loop)
	condition := parts[0]
	if (
		s.tree.kind[condition] != node_kind("Binary")
		or s.tree.flags[condition] != OP_LESS
	): return

	ends := children(s.tree, condition)
	if not is_name(s, ends[0]): return

	name := spelling(s.tree, ends[0])
	bound := ends[1]
	bind_at := binding_of(s, statements, at, name)
	if bind_at.is_none(): return

	first := statements[bind_at.get()]
	if s.tree.flags[first] != 1: return

	bind := children(s.tree, first)
	start := bind[2]
	if s.tree.kind[bind[1]] != node_kind("None") or not plain_number(s, start): return
	if used(s, statements.slice(bind_at.get() + 1, at).get_or([]), name): return

	loop_body := children(s.tree, parts[1])
	if loop_body.is_empty(): return

	last := loop_body[loop_body.length() - 1]
	inner := loop_body.slice(0, loop_body.length() - 1).get_or([])
	if not counts_up(s, last, name): return

	invariant := (
		plain_number(s, bound)
		or (is_name(s, bound) and not wrote(s, inner, spelling(s.tree, bound)))
	)
	if not invariant or wrote(s, inner, name): return
	if used(s, statements.drop(at + 1), name): return

	bind_line := line_start(s, s.tree.offset[first])
	bind_end := last_offset(s.tree, start)
	bind_eol := line_end(s, bind_end)
	if bind_eol >= s.source.length() or not blank(s, bind_line, s.tree.offset[first]): return
	if not blank(s, bind_end, bind_eol): return

	var colon = last_offset(s.tree, bound)
	while (
		colon < s.source.length()
		and (
			s.source[colon] == 32
			or s.source[colon] == 9
			or s.source[colon] == 10
			or s.source[colon] == 13
		)
	): colon += 1
	if colon >= s.source.length() or s.source[colon] != 58: return

	header_end := colon + 1
	last_offset_at := s.tree.offset[last]
	last_line := line_start(s, last_offset_at)
	step_end := last_offset(s.tree, children(s.tree, last)[1])
	step_eol := line_end(s, step_end)
	if not blank(s, last_line, last_offset_at) or not blank(s, step_end, step_eol): return
	if header_end > last_line: return

	whole := text(s, bind_line, step_end)
	if whole.contains("//") or whole.contains("continue"): return

	until := if step_eol > step_end and s.source[step_eol - 1] == 13: step_eol - 1 else: step_eol
	rewritten := (
		text(s, bind_eol + 1, s.tree.offset[loop])
		+ f"for {name} in {written(s, start)}..{written(s, bound)}:"
		+ text(s, header_end, last_line)
	).trim_end_chars("\r\n")
	found := finding(
		"MSL122",
		"error",
		"Count with `for i in start..end:` instead of a `var` and a `while` with `i += 1`",
		s.file,
		s.tree.offset[first],
		s.tree.line[first],
		s.tree.column[first],
	)
	out.append(with_fix(found, bind_line, until, rewritten))

// The findings of the counter-loop rule for the module in `source`.
export fn lint_counter(file: String, source: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(source)
	if parsed.is_error(): return out

	s := Scan(
		tree: parsed.get().clone(),
		facts: analyze(source),
		source: source.to_bytes(),
		file: file.clone(),
	)

	for at in 0..s.tree.kind.length():
		if s.tree.kind[at] != node_kind("List"): continue

		statements := children(s.tree, at)
		for index in 0..statements.length(): counter_while(s, statements, index, out)

	return out

test "a counter while becomes a range loop":
	source := "fn f(n: Int) Int:\n    var total = 0\n    var i = 0\n    while i < n:\n        total += i\n        i += 1\n    return total\n"
	found := lint_counter("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL122")?
	(
		found[0].fix_text
		| expect_equal(expected: "    for i in 0..n:\n        total += i")?
	)

test "a counter used after the loop is left alone":
	source := "fn f(n: Int) Int:\n    var i = 0\n    while i < n:\n        i += 1\n    return i\n"
	lint_counter("t.ms", source).length() | expect_equal(expected: 0)?

test "a bound the loop changes is left alone":
	source := "fn f(n: Int) Int:\n    var i = 0\n    while i < n:\n        n -= 1\n        i += 1\n    return 0\n"
	lint_counter("t.ms", source).length() | expect_equal(expected: 0)?
