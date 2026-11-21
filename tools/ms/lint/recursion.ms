// A function that calls itself on every path never returns (MSL112): no `return`, `try`
// or fault leaves it before the recursive call. Calls resolve through the checker's
// analysis, so a function the checker did not cover yields no finding.
import (
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Analyzed, analyze from "./analysis.ms",
	Finding, finding from "./finding.ms",
)

// How control leaves a block: every path reaches the recursive call first, some path
// returns or faults without recursing, or control reaches the end.
RECURSED := 0
ESCAPED := 1
CONTINUES := 2
// The unary operator number of `try`.
OP_TRY := 3
// The binary operators `or` and `and`, whose right side may not run.
OP_OR := 0
OP_AND := 1

type Scan:
	tree: Syntax
	facts: Analyzed
	own: Int

// The subexpressions that are always evaluated: not the right side of `and`/`or`, a
// lambda body, or a match arm.
fn evaluated(s: Scan, at: Int) List[Int]:
	node := s.tree.kind[at]
	parts := children(s.tree, at)
	if node == node_kind("Lambda"): return []
	if node == node_kind("Match"): return [parts[0]]

	if node == node_kind("Binary"):
		op := s.tree.flags[at]
		if op == OP_OR or op == OP_AND: return [parts[0]]

	return parts

// Whether evaluating `at` can leave the function without returning normally: a `try`,
// or a call whose type the checker did not give (a call that never completes has none).
fn exits(s: Scan, at: Int) Bool:
	node := s.tree.kind[at]
	if node == node_kind("Unary") and s.tree.flags[at] == OP_TRY: return true

	if node == node_kind("Call"):
		known := s.facts.types.get_or(s.tree.id[at], "<invalid>")
		if known == "<invalid>" or known == "Never": return true

	for child in evaluated(s, at):
		if exits(s, child): return true
	return false

// Whether evaluating `at` unconditionally calls this function.
fn reaches_call(s: Scan, at: Int) Bool:
	if s.tree.kind[at] == node_kind("Call"):
		if s.facts.callee.get_or(s.tree.id[at], -1) == s.own: return true
	for child in evaluated(s, at):
		if reaches_call(s, child): return true
	return false

// Branches taken one at a time: any exit is an exit, all recursing is recursing.
fn branches(outcomes: List[Int]) Int:
	if outcomes.contains(ESCAPED): return ESCAPED
	if outcomes.all(fn outcome: outcome == RECURSED): return RECURSED

	return CONTINUES

// The outcome of evaluating `at`; `returned` when its value is the function's result.
fn value(s: Scan, at: Int, returned: Bool) Int:
	if exits(s, at): return ESCAPED

	if s.tree.kind[at] == node_kind("Match"):
		parts := children(s.tree, at)
		if reaches_call(s, parts[0]): return RECURSED

		return branches(
			children(s.tree, parts[1]).map(
				fn arm: arm_outcome(s, arm, returned)
			)
		)

	if reaches_call(s, at): return RECURSED

	return if returned: ESCAPED else: CONTINUES

fn arm_outcome(s: Scan, arm: Int, returned: Bool) Int:
	parts := children(s.tree, arm)
	done := block(s, parts[2])
	if done != CONTINUES: return done
	if s.tree.kind[parts[3]] != node_kind("None"): return value(s, parts[3], returned)

	return if returned: ESCAPED else: CONTINUES

// A loop may run zero times, so only an exit inside it counts.
fn looped(s: Scan, head: Int, body: Int) Int:
	done := value(s, head, false)
	if done == CONTINUES and block(s, body) == ESCAPED: return ESCAPED

	return done

fn statement(s: Scan, at: Int) Int:
	node := s.tree.kind[at]
	parts := children(s.tree, at)

	if node == node_kind("Return"):
		if parts.is_empty() or s.tree.kind[parts[0]] == node_kind("None"): return ESCAPED
		return value(s, parts[0], true)

	if node == node_kind("Bind"): return value(s, parts[2], false)
	if node == node_kind("Assign"): return value(s, parts[1], false)
	if node == node_kind("CallStmt"): return value(s, parts[0], false)

	if node == node_kind("If"):
		condition := value(s, parts[1], false)
		if condition != CONTINUES: return condition

		return branches([block(s, parts[2]), block(s, parts[3])])

	if node == node_kind("While") or node == node_kind("For"): return looped(
		s,
		parts[0],
		parts[1],
	)

	return CONTINUES

fn block(s: Scan, body: Int) Int:
	for at in children(s.tree, body):
		done := statement(s, at)
		if done != CONTINUES: return done

	return CONTINUES

// The findings of the recursion rule for the module in `text`; none when it does not
// parse or the checker does not cover it.
export fn lint_recursion(file: String, text: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	facts := analyze(text)
	if parsed.is_error() or facts.is_none(): return out

	tree := parsed.get()
	known := facts.get()

	for at in children(tree, 0):
		if tree.kind[at] != node_kind("Fn") or tree.flags[at] == 4: continue

		parts := children(tree, at)
		if children(tree, parts[3]).is_empty(): continue

		var own = -1
		for symbol in known.declared.keys():
			if known.declared.get_or(symbol, -1) == tree.id[at]: own = symbol
		if own < 0: continue

		scan := Scan(tree: tree.clone(), facts: known.clone(), own: own)
		if block(scan, parts[3]) != RECURSED: continue

		name := tree.names[tree.a[at]]
		out.append(
			finding(
				"MSL112",
				"error",
				f"{name} calls itself on every path, so it never returns; add a base case that returns before the recursive call",
				file,
				tree.offset[at],
				tree.line[at],
				tree.column[at],
			)
		)

	return out

test "a function that calls itself on every path is reported":
	source := "fn f(n: Int) Int:\n    return f(n - 1)\n"
	found := lint_recursion("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL112")?

test "a base case that returns keeps the recursion legal":
	source := "fn f(n: Int) Int:\n    if n == 0:\n        return 0\n    return f(n - 1)\n"
	lint_recursion("t.ms", source).length() | expect_equal(expected: 0)?
