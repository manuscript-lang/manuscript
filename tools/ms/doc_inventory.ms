// The description inventory and policy check of crates/ms-tooling/src/guide/docgen.rs:
// counts and classifies every declaration and member description, and fails on missing,
// placeholder, terse or restating ones that the backlog does not list.
//   ms run tools/ms/doc_inventory.ms -- MODEL.json BACKLOG.json [COVERAGE.json]
// Prints problems to standard error and exits 1 when there are any; writes the
// inventory as JSON.
import (
	Arg, Command, Matches from "@std/cli/command.ms",
	parse from "@std/data/json.ms",
	read_file, write_file from "@std/os/fs.ms",
	is_alphabetic, is_lowercase, is_numeric, is_uppercase from "@std/unicode.ms",

	run_tool from "./cli.ms",
	Module from "./docgen.ms",
)

type Model:
	modules: List[Module]

type Policy:
	format: Int
	backlog: List[String] = []

type Entry:
	module: String
	declaration: String
	kind: String
	name: String
	contract: String
	described: Bool
	qualified: Bool
	problem: String

type Inventory:
	entries: List[Entry]
	includes_prelude_aliases: Bool
	declarations: Int
	described_declarations: Int
	qualified_declarations: Int
	members: Int
	described_members: Int
	qualified_members: Int

fn placeholders() List[String]:
	return [
		"todo", "tbd", "fixme", "placeholder", "undocumented", "description goes here",
		"documentation goes here"
	]

fn ignored_words() String: "a an the this that these those it its s of for to from with without and or in on at by as is are be can may will field member method function operation case type declaration public exported native standard api value data object property describes describing represents returns holds provides gets sets has about information description documentation named called contains containing stores stored storing reports whether behavior behaviour contract fn record interface int int64 float float64 bool void never string bytes optional result list map set payload"

// Lowercased words of `text`, splitting camel case, punctuation and underscores.
fn description_words(text: String) List[String]:
	var words = List[String]()
	var current = ""
	var previous_lower = false

	for ch in text.chars():
		scalar := ch.scalar_at(0)

		if is_uppercase(scalar) and previous_lower:
			if not current.is_empty():
				words.append(current.clone())
				current = ""

		if is_alphabetic(scalar) or is_numeric(scalar): current = current.concat(
			ch.lower()
		)
		else if not current.is_empty():
			words.append(current.clone())
			current = ""

		previous_lower = is_lowercase(scalar)

	if not current.is_empty(): words.append(current.clone())
	return words

fn problem_of(entry: Entry, doc: String) String:
	raw := doc.trim()
	text := raw.lower()
	if text.is_empty(): return "missing description"

	trimmed := text.trim_start_chars("# `*")
	for placeholder in placeholders():
		if trimmed.starts_with(placeholder): return "placeholder description"

	words := description_words(raw)
	if words.length() < 4: return "description is too terse to state a contract"

	var ignored = Set[String]()
	for word in description_words(f"{entry.name} {entry.declaration}"): ignored.add(
		word.clone()
	)
	for word in ignored_words().split(" "): ignored.add(word.clone())
	for word in words:
		if not ignored.contains(word): return ""
	return "description only restates the API name or kind"

fn inventory(modules: List[Module]) Inventory:
	var report = Inventory([], false, 0, 0, 0, 0, 0, 0)

	for module in modules:
		for d in module.declarations:
			add(
				report,
				Entry(
					module.path.clone(),
					d.name.clone(),
					"declaration",
					d.name.clone(),
					"",
					false,
					false,
					"",
				),
				d.doc,
			)
			for m in d.members:
				add(
					report,
					Entry(
						module.path.clone(),
						d.name.clone(),
						m.kind.clone(),
						m.name.clone(),
						m.contract.clone(),
						false,
						false,
						"",
					),
					m.doc,
				)

	return report

fn add(var report: Inventory, entry: Entry, doc: String) Void:
	var next = entry.clone()
	next.described = not doc.trim().is_empty()
	next.problem = problem_of(next, doc)
	next.qualified = next.problem.is_empty()
	if next.module == "prelude": report.includes_prelude_aliases = true

	if next.kind == "declaration":
		report.declarations += 1
		if next.described: report.described_declarations += 1
		if next.qualified: report.qualified_declarations += 1
	else:
		report.members += 1
		if next.described: report.described_members += 1
		if next.qualified: report.qualified_members += 1

	report.entries.append(next)

fn key_of(entry: Entry) String: f"{entry.module}|{entry.declaration}|{entry.kind}|{entry.name}|{entry.contract}"

fn check(report: Inventory, policy: Policy) List[String]:
	var backlog = Set[String]()
	var problems = List[String]()

	for key in policy.backlog:
		if backlog.contains(key): problems.append(
			f"{key}: duplicate description backlog entry"
		)
		backlog.add(key.clone())

	var seen = Set[String]()

	for entry in report.entries:
		key := key_of(entry)
		if backlog.contains(key) and entry.described: problems.append(
			f"{key}: description exists; remove the stale backlog entry"
		)

		if entry.qualified or (not entry.described and backlog.contains(key)):
			seen.add(key.clone())
			continue

		problems.append(
			f"{key}: {entry.problem}; describe observable behavior, units, defaults, errors or ownership"
		)
		seen.add(key.clone())

	for key in backlog.values():
		if not seen.contains(key): problems.append(
			f"{key}: API no longer exists; remove the stale backlog entry"
		)
	problems.sort()
	return problems

fn json_string(text: String) String:
	var out = "\""

	for ch in text.chars():
		if ch == "\"": out = out.concat("\\\"")
		else if ch == "\\": out = out.concat("\\\\")
		else if ch == "\n": out = out.concat("\\n")
		else if ch == "\r": out = out.concat("\\r")
		else if ch == "\t": out = out.concat("\\t")
		else if ch == "<": out = out.concat("\\u003c")
		else if ch == ">": out = out.concat("\\u003e")
		else if ch == "&": out = out.concat("\\u0026")
		else: out = out.concat(ch)

	return out.concat("\"")

fn to_json(report: Inventory) String:
	var entries = ""

	for i in 0..report.entries.length():
		e := report.entries[i]
		if i > 0: entries = entries.concat(",")
		entries = entries.concat(
			f"\n    \{\n      \"module\": {json_string(e.module)},\n      \"declaration\": {json_string(e.declaration)},\n      \"kind\": {json_string(e.kind)},\n      \"name\": {json_string(e.name)}"
		)
		if not e.contract.is_empty(): entries = entries.concat(
			f",\n      \"contract\": {json_string(e.contract)}"
		)
		entries = entries.concat(
			f",\n      \"described\": {e.described},\n      \"qualified\": {e.qualified}"
		)
		if not e.problem.is_empty(): entries = entries.concat(
			f",\n      \"problem\": {json_string(e.problem)}"
		)
		entries = entries.concat("\n    }")

	listing := if report.entries.is_empty(): "[]" else: f"[{entries}\n  ]"
	return f"\{\n  \"format\": 1,\n  \"includes_prelude_aliases\": {report.includes_prelude_aliases},\n  \"declarations\": {report.declarations},\n  \"described_declarations\": {report.described_declarations},\n  \"members\": {report.members},\n  \"described_members\": {report.described_members},\n  \"qualified_declarations\": {report.qualified_declarations},\n  \"qualified_members\": {report.qualified_members},\n  \"entries\": {listing}\n\}\n"

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
fn show(m: Matches) Void!:
	model := parse[Model](read_file(m.string("model")).wait()?.decode_utf8().get_or(""))?
	policy := parse[Policy](
		read_file(m.string("backlog")).wait()?.decode_utf8().get_or("")
	)?
	if policy.format != 1: return error(
		Error(f"unsupported description policy format {policy.format}")
	)

	report := inventory(model.modules)
	print(
		f"API descriptions: {report.described_declarations}/{report.declarations} declarations, {report.described_members}/{report.members} members (including prelude aliases)"
	)
	print(
		f"Description quality: {report.qualified_declarations}/{report.declarations} declarations, {report.qualified_members}/{report.members} members pass structural checks; semantic review remains required"
	)
	if coverage := m.string_or_none("coverage"): write_file(
		coverage,
		to_json(report).to_bytes(),
	).wait()?

	problems := check(report, policy)
	for problem in problems: print(f"API description: {problem}")
	if not problems.is_empty(): return error(Error(""))

import expect_equal from "@std/test/test.ms"

fn probe(doc: String) String:
	return problem_of(
		Entry("m", "Thing", "declaration", "Thing", "", false, false, ""),
		doc,
	)

test "an empty description is missing":
	expect_equal(probe("  "), "missing description")?

test "a placeholder is rejected":
	expect_equal(probe("TODO: write this"), "placeholder description")?

test "a short description is too terse":
	expect_equal(probe("Holds a thing"), "description is too terse to state a contract")?

test "a description that restates the name is rejected":
	expect_equal(
		probe("The thing declaration is a thing"),
		"description only restates the API name or kind",
	)?

test "a description with new words qualifies":
	expect_equal(probe("Counts the entries waiting in the queue"), "")?

fn inventory_tool() Command:
	return Command(
		name: "doc_inventory.ms",
		about: "Count the described API declarations and check them against the policy",
		args: [
			Arg("model", help: "The model JSON"),
			Arg("backlog", help: "The description policy JSON"),
			Arg(
				"coverage",
				help: "Where to write the coverage JSON",
				required: false,
			),
		],
	)

fn main() Int:
	return run_tool(inventory_tool(), show)
