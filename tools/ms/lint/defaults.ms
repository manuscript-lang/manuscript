// A default that one `if` may override (MSL121): `var x = a` then `if c: x = b` is
// `x := if c: b else: a`. The scalar type of the default comes from the checker's analysis,
// so a function the checker did not cover yields no finding. Uses of the name are
// matched by spelling, and a name passed to a call counts as written, so a doubtful
// case is left alone.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Analyzed, analyze from "./analysis.ms",
	Finding, finding, with_fix from "./finding.ms",
	first_offset, last_offset, span from "./spans.ms",
	has_call, may_write, mentions, spelling from "./uses.ms",
)

type Scan:
	tree: Syntax
	facts: Analyzed
	source: Bytes
	file: String

fn text_of(s: Scan, at: Int) String:
	found := span(s.source, first_offset(s.tree, at), last_offset(s.tree, at))
	if found.is_none(): return ""

	return found.get()

// A literal, a name, or text without interpolation.
fn is_simple(s: Scan, at: Int) Bool:
	node := s.tree.kind[at]
	if (
		node == node_kind("Number")
		or node == node_kind("Bool")
		or node == node_kind("Name")
	): return true
	if node != node_kind("Text"): return false

	return children(s.tree, at).all(fn part: s.tree.flags[part] % 2 == 0)

fn is_scalar(s: Scan, at: Int) Bool:
	known := s.facts.types.get_or(s.tree.id[at], "")
	return ["String", "Int", "Float", "Bool"].contains(known)

// `first` and `second` are consecutive statements of one block; `rest` are the statements
// after them.
fn default_then_override(
	s: Scan,
	first: Int,
	second: Int,
	rest: List[Int],
	var out: List[Finding],
) Void:
	if (
		s.tree.kind[first] != node_kind("Bind")
		or s.tree.kind[second] != node_kind("If")
	): return
	if s.tree.flags[first] != 1: return

	bind := children(s.tree, first)
	pattern := bind[0]
	if s.tree.kind[pattern] != node_kind("PatName"): return
	if s.tree.kind[bind[1]] != node_kind("None"): return

	branch := children(s.tree, second)
	if s.tree.kind[branch[0]] != node_kind("None"): return

	then := children(s.tree, branch[2])
	if then.length() != 1 or not children(s.tree, branch[3]).is_empty(): return

	assign := then[0]
	if s.tree.kind[assign] != node_kind("Assign") or s.tree.flags[assign] != 0: return

	name := spelling(s.tree, pattern)
	if spelling(s.tree, assign) != name: return

	default := bind[2]
	condition := branch[1]
	replacement := children(s.tree, assign)[1]
	if not is_simple(s, default) or not is_scalar(s, default): return

	// `x := if c: b else: a` reads `a` after `c` runs; a call in `c` can change a `var` `a`.
	if s.tree.kind[default] == node_kind("Name") and has_call(s.tree, condition): return
	if mentions(s.tree, condition, name) + mentions(s.tree, replacement, name) > 0: return

	for later in rest:
		if may_write(s.tree, later, name): return

	from := s.tree.offset[first]
	to := last_offset(s.tree, replacement)
	if to > s.source.length() or from < 0 or from > to: return
	if s.source.view(from, to).decode_utf8().get_or("//").contains("//"): return

	a := text_of(s, default)
	c := text_of(s, condition)
	b := text_of(s, replacement)
	if a.is_empty() or c.is_empty() or b.is_empty(): return

	found := finding(
		"MSL121",
		"error",
		"Write the default and the override as one `x := if c: b else: a`",
		s.file,
		s.tree.offset[first],
		s.tree.line[first],
		s.tree.column[first],
	)
	out.append(with_fix(found, from, to, f"{name} := if {c}: {b} else: {a}"))

// The findings of the rule for the module in `text`; none when it does not parse or the
// checker does not cover it.
export fn lint_defaults(file: String, text: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	facts := analyze(text)
	if parsed.is_error() or facts.is_none(): return out

	s := Scan(
		tree: parsed.get().clone(),
		facts: facts.get(),
		source: text.to_bytes(),
		file: file.clone(),
	)

	for at in 0..s.tree.kind.length():
		if s.tree.kind[at] != node_kind("List"): continue

		statements := children(s.tree, at)
		for i in 1..statements.length():
			default_then_override(
				s,
				statements[i - 1],
				statements[i],
				statements.drop(i + 1),
				out,
			)

	return out

test "a default and a one-line override become one conditional":
	source := "fn f(c: Bool) Int:\n    var x = 1\n    if c:\n        x = 2\n    return x\n"
	found := lint_defaults("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL121")?
	found[0].fix_text | expect_equal(expected: "x := if c: 2 else: 1")?

test "a name passed to a call afterwards may change, so it is left alone":
	source := "fn f(c: Bool) Int:\n    var x = 1\n    if c:\n        x = 2\n    bump(x)\n    return x\n"
	lint_defaults("t.ms", source).length() | expect_equal(expected: 0)?
