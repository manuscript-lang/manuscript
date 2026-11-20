// Annotates views with what a diff changed, and explains one finding. Port of
// crates/ms-tooling/src/mark.rs.
import (
	JsonValue from "@std/data/json.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	flag, list_of, number, object, render_document, text, with from "./json_out.ms",
	DiffInput, Finding, compare_facts from "./review.ms",
	Fact, Facts, Node, build_view, model_of, tree_ascii from "./views.ms",
)

// The version of the report documents.
export REPORT_FORMAT := 2

// Entity nodes and calls to changed entities carry the finding's tier and number, and
// flow steps on changed lines carry "changed". The marks are fixed templates.
export fn mark_changes(
	tree: Node,
	findings: List[Finding],
	touched: Map[String, List[Int]],
) Node:
	var marks = Map[String, String]()
	var rank = 0

	for f in findings:
		if f.tier != "INTERNAL":
			rank += 1
			marks.add(f.id.clone(), f"  <- {f.tier} #{rank}")
		else: marks.add(f.id.clone(), "  <- INTERNAL")

	return walk(tree, marks, touched)

fn changed_line(n: Node, touched: Map[String, List[Int]]) Bool:
	if n.line <= 0: return false

	lines := touched.get(n.file)
	if lines.is_none(): return false

	return lines.get().contains(n.line)

fn walk(n: Node, marks: Map[String, String], touched: Map[String, List[Int]]) Node:
	var out = n.clone()
	mark := if n.reference.is_empty(): none else: marks.get(n.reference)

	if m := mark: out.label = out.label.concat(m)
	else if changed_line(n, touched): out.label = out.label.concat("  <- changed")

	var children = List[Node]()
	for child in n.children: children.append(walk(child, marks, touched))
	out.children = children
	return out

// A finding and its LOOK HERE FIRST number (0 when it is internal).
type Selected:
	finding: Finding
	number: Int

fn attention(findings: List[Finding]) List[Finding]:
	var out = List[Finding]()
	for f in findings:
		if f.tier != "INTERNAL": out.append(f.clone())
	return out

fn select(findings: List[Finding], selector: String) Selected!:
	shown := attention(findings)

	if n := selector.parse_int():
		if n < 1 or n > shown.length(): return error(
			Error(
				f"no finding {n}; LOOK HERE FIRST numbers run 1 to {shown.length()}"
			)
		)
		return ok(Selected(finding: shown[n - 1].clone(), number: n))

	var found: Finding? = none
	for f in findings:
		if f.id == selector and found.is_none(): found = f.clone()

	if found.is_none():
		var matches = List[Finding]()
		for f in findings:
			if f.entity == selector: matches.append(f.clone())
		if matches.length() > 1: return error(
			Error(
				f"finding \"{selector}\" is ambiguous; pass a number from LOOK HERE FIRST or a full finding id"
			)
		)
		if matches.is_empty(): return error(
			Error(
				f"no finding \"{selector}\"; pass a number from LOOK HERE FIRST or a finding id"
			)
		)

		found = matches[0].clone()

	chosen := found.get()
	var number = 0
	for i in 0..shown.length():
		if shown[i].id == chosen.id and number == 0: number = i + 1
	return ok(Selected(finding: chosen.clone(), number: number))

fn head_fact(head: Facts, key: String) Fact?:
	for f in head.entities:
		if f.key == key: return f.clone()
	return none

fn diagram_available(found: Finding, head: Facts) Bool:
	if f := head_fact(head, found.id): return (
		f.kind == "fn"
		or f.kind == "method"
		or f.kind == "test"
	)
	return false

fn callers_of(found: Finding, head: Facts) List[Fact]:
	var out = List[Fact]()
	for f in head.entities:
		if f.calls.contains(found.id): out.append(f.clone())
	return out

fn finding_json(f: Finding) JsonValue:
	var out = object()
	out = with(out, "id", text(f.id))
	out = with(out, "tier", text(f.tier))
	out = with(out, "entity", text(f.entity))
	out = with(out, "where", text(f.location))
	out = with(out, "changes", strings_or_null(f.changes))
	out = with(out, "reach", number(f.reach))
	out = with(out, "score", number(f.score))
	out = with(out, "terms", strings_or_null(f.terms))
	if not f.evidence.is_empty(): out = with(out, "evidence", strings(f.evidence))
	return out

fn strings(items: List[String]) JsonValue:
	var out = List[JsonValue]()
	for item in items: out.append(text(item))
	return list_of(out)

fn strings_or_null(items: List[String]) JsonValue:
	if items.is_empty(): return JsonValue.Null
	return strings(items)

// One finding and the source identities needed to investigate it.
export fn explain_json(findings: List[Finding], head: Facts, selector: String) String!:
	chosen := select(findings, selector)?
	found := chosen.finding.clone()
	var callers = List[JsonValue]()

	for f in callers_of(found, head):
		var row = object()
		row = with(row, "id", text(f.key))
		row = with(row, "entity", text(f.name))
		row = with(row, "file", text(f.file))
		row = with(row, "line", number(f.line))
		callers.append(row)

	var diagram = JsonValue.Null
	if diagram_available(found, head):
		diagram = with(with(object(), "view", text("flow")), "entity", text(found.id))

	var out = object()
	out = with(out, "format", number(REPORT_FORMAT))
	out = with(
		out,
		"number",
		if chosen.number == 0: JsonValue.Null else: number(chosen.number),
	)
	out = with(out, "finding", finding_json(found))
	out = with(out, "callers", list_of(callers))
	out = with(out, "diagram", diagram)
	return ok(render_document(out))

// Renders one finding's full score derivation, evidence, and callers. `selector` is the
// display number from LOOK HERE FIRST or a stable finding id.
export fn explain(findings: List[Finding], head: Facts, selector: String) String!:
	chosen := select(findings, selector)?
	found := chosen.finding.clone()
	title := if chosen.number > 0: f"EXPLAIN #{chosen.number} {found.entity}" else: f"EXPLAIN {found.entity}"
	var b = f"{title}\nreport format {REPORT_FORMAT}\n\n"
	b = b.concat(
		f"id       {found.id}\ntier     {found.tier}\nwhere    {found.location}\nreach    {found.reach}\nscore    {found.score}\n"
	)
	b = b.concat("\nWHY\n")
	for c in found.changes: b = b.concat(f"  change   {c}\n")
	for t in found.terms: b = b.concat(f"  term     {t}\n")
	b = b.concat("\nEVIDENCE\n")
	if found.evidence.is_empty(): b = b.concat("  none\n")
	for e in found.evidence: b = b.concat(f"  {e}\n")
	b = b.concat("\nCALLERS\n")

	var callers = List[String]()
	for fact in head.entities:
		for callee in fact.calls:
			if callee == found.id: callers.append(
				f"{fact.name}  {fact.file}:{fact.line}"
			)
	callers.sort()
	if callers.is_empty(): b = b.concat("  none\n")
	for c in callers: b = b.concat(f"  {c}\n")

	if diagram_available(found, head):
		entity := found.id.replace("'", "'\\''")
		b = b.concat(
			f"\nNEXT\n  ms diagram <project> --view flow --entity '{entity}' --diff <diff>\n"
		)
	else: b = b.concat(
		"\nNEXT\n  Inspect the declaration in the diff and its callers; no flow exists for this entity in the current tree.\n"
	)

	return ok(b)

// ---- Tests ----

fn fact(file: String, kind: String, name: String, line: Int) Fact:
	return Fact(
		key: f"{file}#{kind}#{name}",
		file: file,
		kind: kind,
		name: name,
		line: line,
		effects: [],
		error: "",
		tries: 0,
		scopes: 0,
		calls: [],
		external: [],
		slots: [],
		result_ownership: "",
		result_borrow: false,
		receiver: "",
		result: none,
		ty: "fn() Int",
		first: line,
		last: line + 1,
	)

fn program(add_effect: Bool) Facts:
	var say = fact("r.ms", "fn", "say", 3)
	say.effects = ["io"]
	say.reach = ["io"]
	say.external = ["@std/io/io.ms#stdout"]

	var add = fact("r.ms", "fn", "add", 7)
	var run = fact("r.ms", "fn", "run", 10)
	run.exported = true
	run.calls = [add.key.clone()]

	if add_effect:
		add.effects = ["io"]
		add.reach = ["io"]
		add.calls = [say.key.clone()]
		run.effects = ["io"]
		run.reach = ["io"]

	return Facts(entities: [add, run, say], imports: [], flows: [])

fn input_at(lines: List[Int]) DiffInput:
	return DiffInput(added: Set[String](), touched: {"r.ms": lines}, base_checked: true)

fn error_text(result: String!) String:
	if result.is_error(): return result.err().message.clone()
	return ""

test "a diff marks the tree and explains a finding":
	head := program(true)
	findings := compare_facts(program(false), head, input_at([8]))
	tree := build_view(model_of(head.clone()), "calls", "run", 0).get()
	marked := mark_changes(tree, findings, {})
	expect_true(tree_ascii(marked).contains("<- EFFECT+ #"))?

	explained := explain(findings, head, "1").get_or("")
	expect_true(explained.starts_with("EXPLAIN #1 "))?
	expect_true(explained.contains("\nCALLERS\n"))?
	expect_true(error_text(explain(findings, head, "9")).starts_with("no finding 9;"))?

test "an explanation keeps the stable id and handles removed entities":
	head := program(true)
	findings := compare_facts(program(false), head, input_at([8]))
	id := findings[0].id.clone()
	json := explain_json(findings, head, "1").get_or("")
	expect_true(json.contains(f"\"entity\": \"{id}\""))?
	expect_true(explain(findings, head, "1").get_or("").contains(f"--entity '{id}'"))?

	empty := Facts(entities: [], imports: [], flows: [])
	removed := compare_facts(head, empty, input_at([]))
	expect_true(
		explain_json(removed, empty, "1").get_or("").contains(
			"\"diagram\": null"
		)
	)?
	expect_true(not explain(removed, empty, "1").get_or("").contains("ms diagram"))?

test "an ambiguous finding name needs a number or an id":
	facts := Facts(
		entities: [
			fact("a.ms", "fn", "same", 1),
			fact("b.ms", "fn", "same", 1),
		],
		imports: [],
		flows: [],
	)
	empty := Facts(entities: [], imports: [], flows: [])
	findings := compare_facts(empty, facts, input_at([]))
	expect_true(error_text(explain(findings, facts, "same")).contains("ambiguous"))?
	expect_true(explain(findings, facts, "a.ms#fn#same").is_ok())?
