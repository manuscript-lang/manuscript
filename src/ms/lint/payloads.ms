// A capitalised match payload name that coincides with a type or a case (MSL106): the
// pattern still binds a fresh value for it instead of matching, which is almost never
// what was meant. The checker says which names conflict and with what; this rule words
// the finding and, when the payload is an enum with that case, shows how to match it.
import (
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Analyzed, Conflict, analyze from "./analysis.ms",
	Finding, finding from "./finding.ms",
	spelling from "./uses.ms",
)

// The arm of the tree with syntax node id `id`, or -1.
fn arm_at(tree: Syntax, id: Int) Int:
	for at in 0..tree.kind.length():
		if tree.kind[at] == node_kind("Arm") and tree.id[at] == id: return at
	return -1

// The payload name written at `offset`.
fn binding_name(tree: Syntax, offset: Int) String:
	for at in 0..tree.kind.length():
		if tree.kind[at] == node_kind("ArmBinding") and tree.offset[at] == offset: return spelling(
			tree,
			at,
		)
	return ""

// The path an arm names, as written: `Pair` or `Shape.Circle`.
fn path_text(tree: Syntax, at: Int) String:
	if tree.kind[at] == node_kind("Name"): return spelling(tree, at)
	if tree.kind[at] != node_kind("Member"): return ""

	return path_text(tree, children(tree, at)[0]) + "." + spelling(tree, at)

// The names of the arm's payload bindings, in order.
fn payload_names(tree: Syntax, arm: Int) List[String]:
	var names = List[String]()
	for binding in children(tree, children(tree, arm)[1]): names.append(
		spelling(tree, binding)
	)
	return names

// A name for the payload that no binding of the arm uses.
fn fresh_payload(names: List[String]) String:
	var payload = "payload"
	var suffix = 2

	while names.contains(payload):
		payload = f"payload{suffix}"
		suffix += 1

	return payload

// The remedy for a payload that is the enum owning the case: a helper that matches it.
fn nested_remedy(tree: Syntax, arm: Int, conflict: Conflict) String:
	var names = payload_names(tree, arm)
	payload := fresh_payload(names)
	var index = 0
	for position in 0..names.length():
		if (
			tree.offset[
				children(tree, children(tree, arm)[1])[position]
			] == conflict.offset
		): index = position
	names[index] = payload.clone()

	path := if conflict.contract.is_empty(): path_text(tree, children(tree, arm)[0]) else: conflict.contract
	joined := names.join(", ")
	nested := conflict.nested
	return f"; nested patterns are unsupported: write '{path}({joined}):', handle the payload in a separate helper using 'match {payload}:' with a '{nested}:' arm"

fn message(tree: Syntax, conflict: Conflict) String:
	name := binding_name(tree, conflict.offset)
	identity := conflict.identity
	payload := conflict.payload
	said := f"{name} is {identity}, but this pattern creates a fresh binding for every {payload} payload; use a lowercase binding name if intentional"
	arm := arm_at(tree, conflict.arm)
	if conflict.nested.is_empty() or arm < 0: return said

	return said + nested_remedy(tree, arm, conflict)

// The findings of the payload-name rule for the module in `source`.
export fn lint_payloads(file: String, source: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(source)
	if parsed.is_error(): return out

	facts := analyze(source)
	if facts.is_none(): return out

	for conflict in facts.get().conflicts:
		out.append(
			finding(
				"MSL106",
				"error",
				message(parsed.get(), conflict.clone()),
				file,
				conflict.offset,
				conflict.line,
				conflict.column,
			)
		)
	return out

test "a capitalised payload that is a case of the payload's enum is reported with its remedy":
	source := "enum Failure:\n    NotFound\n    Denied\n\nenum Envelope:\n    Pair(left: Failure, right: Failure)\n\nfn use(value: Envelope) Int:\n    match value:\n        Pair(_payload, NotFound): return 1\n"
	found := lint_payloads("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL106")?
	found[0].line | expect_equal(expected: 10)?
	(
		found[0].message.contains("'Pair(_payload, payload):'")
		| expect_equal(expected: true)?
	)

test "a payload named like a type is reported without a remedy":
	source := "type Item:\n    value: Int\n\nenum Wrap:\n    One(inner: Int)\n\nfn use(w: Wrap) Int:\n    match w:\n        One(Item): return 1\n"
	found := lint_payloads("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].message.contains("is a type name") | expect_equal(expected: true)?
	found[0].message.contains("nested patterns") | expect_equal(expected: false)?

test "a lowercase payload is left alone":
	source := "enum Wrap:\n    One(inner: Int)\n\nfn use(w: Wrap) Int:\n    match w:\n        One(inner): return inner\n"
	lint_payloads("t.ms", source).length() | expect_equal(expected: 0)?
