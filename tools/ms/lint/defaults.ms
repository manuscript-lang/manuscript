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
)

type Scan:
	tree: Syntax
	facts: Analyzed
	source: Bytes
	file: String

fn spelling(s: Scan, at: Int) String:
	return s.tree.names[s.tree.a[at]].clone()

fn text_of(s: Scan, at: Int) String:
	found := span(s.source, first_offset(s.tree, at), last_offset(s.tree, at))
	if found.is_none(): return ""

	return found.get()

// How many times the name `name` is spelled in the subtree at `at`.
fn mentions(s: Scan, at: Int, name: String) Int:
	var total = if s.tree.kind[at] == node_kind("Name") and spelling(s, at) == name: 1 else: 0
	for child in children(s.tree, at): total += mentions(s, child, name)
	return total

// Whether the subtree at `at` assigns the name or passes it to a call, which may change
// it.
fn may_write(s: Scan, at: Int, name: String) Bool:
	node := s.tree.kind[at]
	if (
		node == node_kind("Assign")
		and s.tree.flags[at] % 2 == 0
		and spelling(s, at) == name
	):
		return true

	if node == node_kind("Call"):
		for argument in children(s.tree, children(s.tree, at)[1]):
			value := children(s.tree, argument)[0]
			if s.tree.kind[value] == node_kind("Name") and spelling(s, value) == name: return true

	for child in children(s.tree, at):
		if may_write(s, child, name): return true
	return false

fn has_call(s: Scan, at: Int) Bool:
	if s.tree.kind[at] == node_kind("Call"): return true

	for child in children(s.tree, at):
		if has_call(s, child): return true
	return false

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

	name := spelling(s, pattern)
	if spelling(s, assign) != name: return

	default := bind[2]
	condition := branch[1]
	replacement := children(s.tree, assign)[1]
	if not is_simple(s, default) or not is_scalar(s, default): return

	// `x := if c: b else: a` reads `a` after `c` runs; a call in `c` can change a `var` `a`.
	if s.tree.kind[default] == node_kind("Name") and has_call(s, condition): return
	if mentions(s, condition, name) + mentions(s, replacement, name) > 0: return

	for later in rest:
		if may_write(s, later, name): return

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
