// The syntax-only match rule: a match written inside another match's arms (MSL107).
// Matches the checker builds for `if value := x:` do not count, and the rules that need
// the scrutinee's type (MSL108 and MSL109) wait for the checker's facts.
import (
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Finding, finding from "./finding.ms",
)

NESTED := "Nested match obscures control flow; bind the outer payload with an early exit, use a compatible trailing '?', or call a small helper"

// Whether the match at `at` was written as `match`, not made from an `if` binding.
fn written(tree: Syntax, at: Int, arm: Int) Bool:
	parts := children(tree, at)
	if parts.length() < 2: return false

	arms := children(tree, parts[1])
	if arms.is_empty(): return true

	return tree.kind[arms[0]] != arm or tree.flags[arms[0]] != 1

fn scan(
	tree: Syntax,
	at: Int,
	depth: Int,
	file: String,
	kinds: List[Int],
	var out: List[Finding],
) Void:
	is_match := tree.kind[at] == kinds[0]
	var inner = depth

	if is_match and written(tree, at, kinds[1]):
		if depth > 0:
			out.append(
				finding(
					"MSL107",
					"error",
					NESTED,
					file,
					tree.offset[at],
					tree.line[at],
					tree.column[at],
				)
			)
		inner = depth + 1

	for child in children(tree, at): scan(tree, child, inner, file, kinds, out)

// The nested-match findings of the module in `text`; none when it does not parse.
export fn lint_matches(file: String, text: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	if parsed.is_error(): return out

	tree := parsed.get()
	kinds := [node_kind("Match"), node_kind("Arm")]
	scan(tree, 0, 0, file, kinds, out)
	return out

test "a match inside an arm is nested, a sibling match is not":
	source := "fn f(x: Int) Int:\n\tmatch x:\n\t\t1:\n\t\t\tmatch x:\n\t\t\t\t_: return 1\n\t\t_: return 2\n\nfn g(x: Int) Int:\n\tmatch x:\n\t\t_: return 3\n"
	found := lint_matches("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL107")?
	found[0].line | expect_equal(expected: 4)?
