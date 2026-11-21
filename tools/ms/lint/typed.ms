// The lint rules that read the checker's facts. Each reports only what the facts prove,
// so a node the checker did not type yields no finding.
import (
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Facts, kind_of, read_facts from "./facts.ms",
	Finding, finding from "./finding.ms",
	lint_typed_calls from "./typed_calls.ms",
)

// `Optional.get()` without a default faults when the value is absent (MSL110).
fn optional_get(tree: Syntax, facts: Facts, file: String, var out: List[Finding]) Void:
	call := node_kind("Call")
	member := node_kind("Member")

	for at in 0..tree.kind.length():
		if tree.kind[at] != call: continue

		parts := children(tree, at)
		callee := parts[0]
		if tree.kind[callee] != member or tree.names[tree.a[callee]] != "get": continue
		if not children(tree, parts[1]).is_empty(): continue

		receiver := children(tree, callee)[0]
		if kind_of(facts, tree.id[receiver]) != "Optional": continue

		out.append(
			finding(
				"MSL110",
				"warning",
				"Optional.get() without a default faults when the value is absent; use 'if value := ...:', use get_or(default), or get_or_else",
				file,
				tree.offset[at],
				tree.line[at],
				tree.column[at],
			)
		)

// The findings of the typed rules for the module in `text`, given its checker facts;
// none when it does not parse.
export fn lint_typed(file: String, text: String, facts: Facts) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	if parsed.is_error(): return out

	optional_get(parsed.get(), facts, file, out)
	out.extend(
		lint_typed_calls(
			parsed.get().clone(),
			facts.clone(),
			text.to_bytes(),
			file,
		)
	)
	return out

test "a get on an Optional the checker typed is reported":
	source := "fn f(x: Int?) Int:\n    return x.get()\n"
	tree := parse(source).get()
	var found = List[Finding]()

	for at in 0..tree.kind.length():
		if tree.kind[at] == node_kind("Name") and tree.names[tree.a[at]] == "x":
			document := (
				"{\"nodes\": [{\"id\": "
				+ tree.id[at].to_string()
				+ ", \"kind\": \"Optional\"}]}"
			)
			facts := read_facts(document)
			found = lint_typed("t.ms", source, facts.get())

	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL110")?
