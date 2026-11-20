// Whether control can fall through a statement, from the syntax tree alone, and the
// statements that follow one that cannot (MSL103). The checker computes the same fact
// with the types of the calls it meets; here only `panic`, the standard library's one
// `Never` function, is known to stop.
import (
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Finding, finding from "./finding.ms",
)

type Kinds:
	ret: Int
	jump: Int
	conditional: Int
	loop: Int
	until: Int
	call_stmt: Int
	call: Int
	name: Int
	truth: Int
	pattern_match: Int
	absent: Int
	list: Int
	cut: Int
	next: Int
	lambda: Int

fn kinds() Kinds:
	return Kinds(
		ret: node_kind("Return"),
		jump: node_kind("Break"),
		conditional: node_kind("If"),
		loop: node_kind("For"),
		until: node_kind("While"),
		call_stmt: node_kind("CallStmt"),
		call: node_kind("Call"),
		name: node_kind("Name"),
		truth: node_kind("Bool"),
		pattern_match: node_kind("Match"),
		absent: node_kind("None"),
		list: node_kind("List"),
		cut: node_kind("Break"),
		next: node_kind("Continue"),
		lambda: node_kind("Lambda"),
	)

// What a walk over statements learns: whether control falls through, and whether a
// `break` of the enclosing loop is reachable.
type Flow:
	falls: Bool
	breaks: Bool

// Whether the expression at `at` is a call of `panic`.
fn stops(tree: Syntax, k: Kinds, at: Int) Bool:
	if tree.kind[at] != k.call: return false

	callee := children(tree, at)[0]
	return tree.kind[callee] == k.name and tree.names[tree.a[callee]] == "panic"

// Whether a `break` of the enclosing loop sits in the expression subtree at `at`: a
// match arm of an expression can hold one. A lambda body breaks nothing of this
// function.
fn has_break(tree: Syntax, k: Kinds, at: Int) Bool:
	if tree.kind[at] == k.cut: return true
	if tree.kind[at] == k.lambda: return false

	for child in children(tree, at):
		if has_break(tree, k, child): return true
	return false

// The flow of the statement list at `at`.
fn block_flow(tree: Syntax, k: Kinds, at: Int) Flow:
	var falls = true
	var breaks = false

	for statement in children(tree, at):
		step := flow(tree, k, statement)

		if falls:
			breaks = breaks or step.breaks
			falls = step.falls

	return Flow(falls: falls, breaks: breaks)

// The flow of one statement.
fn flow(tree: Syntax, k: Kinds, at: Int) Flow:
	kind := tree.kind[at]
	if kind == k.cut: return Flow(falls: false, breaks: true)
	if kind == k.next: return Flow(falls: false, breaks: false)
	if kind == k.ret: return Flow(falls: false, breaks: has_break(tree, k, at))

	parts := children(tree, at)

	if kind == k.conditional:
		then := block_flow(tree, k, parts[2])
		var other = Flow(falls: true, breaks: false)
		if not children(tree, parts[3]).is_empty(): other = block_flow(
			tree,
			k,
			parts[3],
		)
		return Flow(
			falls: then.falls or other.falls,
			breaks: then.breaks or other.breaks,
		)

	if kind == k.until:
		body := block_flow(tree, k, parts[1])
		forever := tree.kind[parts[0]] == k.truth and tree.flags[parts[0]] % 2 == 1
		return Flow(
			falls: not forever or body.breaks,
			breaks: has_break(tree, k, parts[0]),
		)

	if kind == k.call_stmt:
		value := parts[0]
		if stops(tree, k, value): return Flow(falls: false, breaks: false)
		if tree.kind[value] == k.pattern_match: return match_flow(tree, k, value)

	if kind == k.loop: return Flow(falls: true, breaks: has_break(tree, k, parts[0]))

	return Flow(falls: true, breaks: has_break(tree, k, at))

// A `match` statement stops when every arm does.
fn match_flow(tree: Syntax, k: Kinds, at: Int) Flow:
	arms := children(tree, children(tree, at)[1])
	var falls = arms.is_empty()
	var breaks = false

	for arm in arms:
		parts := children(tree, arm)
		body := block_flow(tree, k, parts[2])
		breaks = breaks or body.breaks

		value_stops := tree.kind[parts[3]] != k.absent and stops(tree, k, parts[3])
		if body.falls and not value_stops: falls = true

	return Flow(falls: falls, breaks: breaks)

// The statements after one control cannot leave.
fn unreachable(
	tree: Syntax,
	k: Kinds,
	file: String,
	at: Int,
	var out: List[Finding],
) Void:
	var reachable = true

	for statement in children(tree, at):
		if not reachable: out.append(
			finding(
				"MSL103",
				"warning",
				"Statement is unreachable",
				file,
				tree.offset[statement],
				tree.line[statement],
				tree.column[statement],
			)
		)
		if reachable and not flow(tree, k, statement).falls: reachable = false

// The findings of the flow rules for the module in `text`; none when it does not parse.
export fn lint_flow(file: String, text: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	if parsed.is_error(): return out

	tree := parsed.get()
	k := kinds()
	for at in 0..tree.kind.length():
		if tree.kind[at] == k.list: unreachable(tree, k, file, at, out)
	return out

test "statements after a return are unreachable":
	found := lint_flow("t.ms", "fn f() Int:\n    return 1\n    print(2)\n")
	found.length() | expect_equal(expected: 1)?
	found[0].line | expect_equal(expected: 3)?
