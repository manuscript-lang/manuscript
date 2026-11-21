// A resource closed at scope end whose type can report a failure only through a
// separate method (MSL114): the scope's close does not run `flush` or `commit`, so a
// failure of that step surfaces only if the binding is flushed first. The checker
// supplies the bindings that close at scope end, the name nodes that move a value out
// and the finisher each type offers; the paths that still hold the value at the end of
// the scope are followed here, on the syntax table.
import (
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Analyzed, Resource, analyze from "./analysis.ms",
	Finding, finding from "./finding.ms",
	spelling from "./uses.ms",
)

// Whether the binding still holds its resource at a point of the flow. `Gone` is a
// path that does not continue (a `return`, or a `break` out of the analysed block).
enum Held:
	Yes
	No
	Gone

type Scan:
	tree: Syntax
	facts: Analyzed
	// The bindings that some `flush` or `commit` call names.
	finished: Map[Int, Bool] = Map[Int, Bool]()
	// The bindings that a name node moves out.
	moved: Map[Int, Bool] = Map[Int, Bool]()

// The path being followed: the binding, and whether some path reaches the end of its
// scope still holding the value.
type Flow:
	binding: Int
	kept: Bool = false

// Whether the subtree at `at` moves the followed binding out.
fn has_move(s: Scan, flow: Flow, at: Int) Bool:
	id := s.tree.id[at]
	if s.facts.moves.get_or(id, false) and s.facts.bound.get_or(id, -1) == flow.binding: return true

	for child in children(s.tree, at):
		if has_move(s, flow, child): return true
	return false

// The state after an `if`: the paths that continue decide, and the value is gone only
// when every one that continues has moved it.
fn join(then: Held, other: Held) Held:
	if then == Held.Gone: return other
	if other == Held.Gone: return then
	if then == Held.No and other == Held.No: return Held.No

	return Held.Yes

// The state after the statements of `body` (a List node, or an absent branch) from
// `state`; `depth` counts the loops entered since the binding's block, whose `break` and
// `continue` stay inside it.
fn run(s: Scan, body: Int, state: Held, depth: Int, var flow: Flow) Held:
	if s.tree.kind[body] != node_kind("List"): return state

	var at = state

	for statement in children(s.tree, body):
		at = step(s, statement, at, depth, flow)
		if at == Held.Gone: return Held.Gone

	return at

fn step(s: Scan, statement: Int, state: Held, depth: Int, var flow: Flow) Held:
	kind := s.tree.kind[statement]
	parts := children(s.tree, statement)

	if kind == node_kind("Return"):
		returns_it := not parts.is_empty() and has_move(s, flow, parts[0])
		if state == Held.Yes and not returns_it: flow.kept = true
		return Held.Gone

	if kind == node_kind("Break") or kind == node_kind("Continue"):
		if depth == 0 and state == Held.Yes: flow.kept = true
		if depth == 0: return Held.Gone

		return state

	if kind == node_kind("If"):
		held := if has_move(s, flow, parts[1]): Held.No else: state
		then := run(s, parts[2], held, depth, flow)
		other := run(s, parts[3], held, depth, flow)
		return join(then, other)

	if kind == node_kind("While") or kind == node_kind("For"):
		held := if has_move(s, flow, parts[0]): Held.No else: state
		run(s, parts[1], held, depth + 1, flow)
		return held

	// A binding, an assignment, a call statement or anything else: the value is moved
	// when any expression in it moves it.
	if has_move(s, flow, statement): return Held.No

	return state

// Whether some path through `rest`, the statements after the binding, reaches the end
// of its scope still holding the value. A value that no path moves is closed there.
fn closed_here(s: Scan, binding: Int, rest: List[Int]) Bool:
	if not s.moved.get_or(binding, false): return true

	var flow = Flow(binding: binding)
	var state = Held.Yes

	for statement in rest:
		state = step(s, statement, state, 0, flow)
		if state == Held.Gone: break

	return flow.kept or state == Held.Yes

// The bindings a `flush` or `commit` call names, and the bindings a name node moves.
fn scan_uses(tree: Syntax, facts: Analyzed) Scan:
	var s = Scan(tree: tree.clone(), facts: facts.clone())

	for at in 0..tree.kind.length():
		id := tree.id[at]
		bound := facts.bound.get_or(id, -1)
		if facts.moves.get_or(id, false) and bound >= 0: s.moved.add(bound, true)
		if tree.kind[at] != node_kind("Call"): continue

		callee := children(tree, at)[0]
		if tree.kind[callee] != node_kind("Member"): continue

		name := spelling(tree, callee)
		holder := children(tree, callee)[0]
		held := facts.bound.get_or(tree.id[holder], -1)
		if (name == "flush" or name == "commit") and held >= 0: s.finished.add(
			held,
			true,
		)

	return s

// The resource bindings of the module, by the node that introduces them.
fn resource_at(facts: Analyzed, pattern: Int) Resource?:
	for resource in facts.resources:
		if resource.decl == pattern: return resource.clone()
	return none

// The findings of the unflushed-resource rule for the module in `source`.
export fn lint_flush(file: String, source: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(source)
	if parsed.is_error(): return out

	facts := analyze(source)
	if facts.is_none(): return out

	s := scan_uses(parsed.get(), facts.get())

	for at in 0..s.tree.kind.length():
		if s.tree.kind[at] != node_kind("List"): continue

		statements := children(s.tree, at)

		for index in 0..statements.length():
			bind := statements[index]
			if s.tree.kind[bind] != node_kind("Bind"): continue

			pattern := children(s.tree, bind)[0]
			if s.tree.kind[pattern] != node_kind("PatName"): continue

			found := resource_at(s.facts, s.tree.id[pattern])
			if found.is_none(): continue

			resource := found.get()
			if (
				not resource.followed
				or resource.finisher.is_empty()
				or s.finished.get_or(resource.binding, false)
				or not closed_here(
					s,
					resource.binding,
					statements.drop(index + 1),
				)
			): continue

			name := resource.name
			finisher := resource.finisher
			out.append(
				finding(
					"MSL114",
					"error",
					f"`{name}` is closed when its scope ends, which does not run `{finisher}`; call `{name}.{finisher}()?` before the scope ends to handle its failure",
					file,
					resource.offset,
					resource.line,
					resource.column,
				)
			)

	return out

test "a resource that is never flushed is reported":
	source := "type Journal:\n    lines: Int\n\nfn move Journal.close() Void!:\n    void self.lines\n    return ok()\n\nfn var Journal.flush() Result[Void, Error]:\n    return ok()\n\nexport fn forgets() Int:\n    journal := Journal(1)\n    return journal.lines\n"
	found := lint_flush("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL114")?
	found[0].line | expect_equal(expected: 12)?

test "a flushed resource is left alone":
	source := "type Journal:\n    lines: Int\n\nfn move Journal.close() Void!:\n    void self.lines\n    return ok()\n\nfn var Journal.flush() Result[Void, Error]:\n    return ok()\n\nexport fn flushes() Result[Int, Error]:\n    var journal = Journal(2)\n    journal.flush()?\n    return ok(journal.lines)\n"
	lint_flush("t.ms", source).length() | expect_equal(expected: 0)?
