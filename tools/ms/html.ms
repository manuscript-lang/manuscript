// The interactive page: one self-contained HTML file that embeds the fact model, so it
// opens offline and needs no server or library. Port of crates/ms-tooling/src/html.rs;
// the Rust code is the oracle (`ms-tooling-dev html HEAD [BASE]`).
//
// The data is compact so a program with thousands of functions stays small: files are
// interned, entities are arrays that refer to each other by index, and flows are arrays
// of
// `[kind, label, callee, children]`.
//   ms run tools/ms/html.ms -- HEAD.json SOURCE_DIR [BASE.json]
import (
	Arg, Command, Matches from "@std/cli/command.ms",
	JsonValue, parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	read_file from "@std/os/fs.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	run_tool from "./cli.ms",
	flag, list_of, number, object, render_compact, text, with from "./json_out.ms",
	DiffInput, compare_facts from "./review.ms",
	Fact, Facts, Node, Slot from "./views.ms",
	files from "@data",
)

// Labels are source lines; longer ones add bytes without adding meaning.
LABEL_CAP := 100
// Most hints one page embeds; later ones are dropped so a huge program stays loadable.
export HINT_CAP := 200000

// The checked type of one identifier occurrence, positioned as the page reads source: a
// zero-based line and a UTF-16 column.
export type TypeHint:
	file: String
	line: Int
	col: Int
	len: Int
	ty: String

type Index:
	files: List[String]
	file_ix: Map[String, Int]
	entity_ix: Map[String, Int]

fn ints(values: List[Int]) JsonValue:
	var out = List[JsonValue]()
	for v in values: out.append(number(v))
	return list_of(out)

fn strings(items: List[String]) JsonValue:
	var out = List[JsonValue]()
	for item in items: out.append(text(item))
	return list_of(out)

fn indices(ix: Index, keys: List[String]) JsonValue:
	var out = List[Int]()
	for k in keys:
		if i := ix.entity_ix.get(k): out.append(i)
	return ints(out)

fn passing_mode(s: Slot) String: if s.exclusive: "var" else: s.mode.clone()

fn slot_json(ix: Index, s: Slot, parameter: Bool) JsonValue:
	var fields = [
		text(s.name),
		text(s.ty),
		number(if s.exclusive: 1 else: 0),
		indices(ix, s.refs),
	]
	if parameter: fields.append(text(passing_mode(s)))
	return list_of(fields)

fn flow_json(ix: Index, nodes: List[Node]) JsonValue:
	var out = List[JsonValue]()

	for n in nodes:
		callee := ix.entity_ix.get(n.reference).get_or(-1)
		out.append(
			list_of(
				[
					text(n.kind),
					text(first_chars(n.label, LABEL_CAP)),
					number(callee),
					flow_json(ix, n.children),
				]
			)
		)

	return list_of(out)

// The first `count` scalars of `value`.
fn first_chars(value: String, count: Int) String:
	var out = ""
	var taken = 0

	for ch in value.chars():
		if taken >= count: break

		out = out.concat(ch)
		taken += 1

	return out

fn entity_json(facts: Facts, ix: Index, f: Fact) JsonValue:
	var flow = List[Node]()
	for entry in facts.flows:
		if entry.key == f.key: flow = entry.steps.clone()

	callable := f.kind == "fn" or f.kind == "method"
	var slots = List[JsonValue]()
	for s in f.slots: slots.append(slot_json(ix, s, callable))

	var result = number(0)
	if r := f.result: result = list_of(
		[text(r.ty), indices(ix, r.refs), text(f.result_ownership)]
	)
	return list_of(
		[
			number(ix.file_ix.get(f.file).get_or(0)),
			text(f.kind),
			text(f.name),
			number(f.line),
			number(if f.exported: 1 else: 0),
			strings(f.effects),
			text(f.error),
			number(f.scopes),
			indices(ix, f.calls),
			strings(f.external),
			list_of(slots),
			result,
			flow_json(ix, flow),
			number(f.first),
			number(f.last),
			text(
				if f.label.is_empty(): f.name.clone() else: f.label.clone()
			),
		]
	)

type HintRow:
	file: Int
	line: Int
	col: Int
	len: Int
	ty: Int

fn compare_rows(a: HintRow, b: HintRow) Int:
	if a.file != b.file: return if a.file < b.file: -1 else: 1
	if a.line != b.line: return if a.line < b.line: -1 else: 1
	if a.col != b.col: return if a.col < b.col: -1 else: 1
	if a.len != b.len: return if a.len < b.len: -1 else: 1
	if a.ty != b.ty: return if a.ty < b.ty: -1 else: 1

	return 0

fn capped_hints(hints: List[TypeHint]) List[TypeHint]:
	if hints.length() <= HINT_CAP: return hints.clone()
	return hints.slice(0, HINT_CAP).get_or([])

// Hints grouped as `[type table, [file index, line, col, len, type index, ...]]` with
// each file's entries in source order.
fn hints_json(ix: Index, hints: List[TypeHint]) JsonValue:
	var table = List[String]()
	var seen = Map[String, Int]()
	var rows = List[HintRow]()

	for h in capped_hints(hints):
		file := ix.file_ix.get(h.file)
		if file.is_none(): continue

		var at = seen.get(h.ty).get_or(-1)

		if at < 0:
			at = table.length()
			seen.add(h.ty.clone(), at)
			table.append(h.ty.clone())

		rows.append(
			HintRow(
				file: file.get(),
				line: h.line,
				col: h.col,
				len: h.len,
				ty: at,
			)
		)

	rows.sort(compare_rows)

	var flat = List[Int]()

	for r in rows:
		flat.append(r.file)
		flat.append(r.line)
		flat.append(r.col)
		flat.append(r.len)
		flat.append(r.ty)

	return list_of([strings(table), ints(flat)])

// The whole program as one interactive page. `base`, when given, is the program before
// a diff: the page marks the changed entities and lists what changed; `hints` give each
// identifier its checked type; `sources` maps each file to its text. The data is
// escaped for embedding in a script element, so no program text can close it.
export fn html_page(
	page: String,
	facts: Facts,
	sources: Map[String, String],
	hints: List[TypeHint],
	base: Facts? = none,
) String:
	var ix = Index(
		files: [],
		file_ix: Map[String, Int](),
		entity_ix: Map[String, Int](),
	)

	for f in facts.entities:
		if not ix.file_ix.contains(f.file):
			ix.file_ix.add(f.file.clone(), ix.files.length())
			ix.files.append(f.file.clone())

	for entry in facts.imports:
		if not ix.file_ix.contains(entry.file):
			ix.file_ix.add(entry.file.clone(), ix.files.length())
			ix.files.append(entry.file.clone())

	for i in 0..facts.entities.length(): ix.entity_ix.add(
		facts.entities[i].key.clone(),
		i,
	)

	var modules = List[JsonValue]()
	for entry in facts.imports:
		modules.append(
			list_of(
				[
					number(ix.file_ix.get(entry.file).get_or(0)),
					strings(entry.paths),
				]
			)
		)

	var entities = List[JsonValue]()
	for f in facts.entities: entities.append(entity_json(facts, ix, f))

	var texts = List[JsonValue]()
	for file in ix.files: texts.append(text(sources.get(file).get_or("")))

	var data = object()
	data = with(data, "f", strings(ix.files))
	data = with(data, "s", list_of(texts))
	data = with(data, "m", list_of(modules))
	data = with(data, "e", list_of(entities))
	data = with(data, "t", hints_json(ix, hints))

	// [entity index or -1 when removed, name, tier, what changed]
	if previous := base:
		var rows = List[JsonValue]()
		input := DiffInput(
			added: Set[String](),
			touched: Map[String, List[Int]](),
			base_checked: true,
		)
		for f in compare_facts(previous, facts, input):
			rows.append(
				list_of(
					[
						number(
							ix.entity_ix.get(f.id).get_or(
								-1
							)
						),
						text(f.entity),
						text(f.tier),
						strings(f.changes),
					]
				)
			)
		data = with(data, "x", list_of(rows))

	marker := "__DATA__"
	at := page.index_of(marker).get_or(-1)
	if at < 0: return page.clone()

	return (
		page.slice(0, at)
		+ render_compact(data)
		+ page.slice(at + marker.length(), page.length())
	)

// ---- Entry ----

fn load(path: String) Facts!:
	return ok(parse[Facts](read_file(path).wait()?.decode_utf8().get_or(""))?)

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.console.write
fn html_tool() Command:
	return Command(
		name: "html.ms",
		about: "Render the interactive page of a project's facts",
		args: [
			Arg("head", help: "HEAD.json"),
			Arg(
				"sources",
				help: "The directory the facts' files are under",
			),
			Arg(
				"base",
				help: "BASE.json, to mark what changed",
				required: false,
			),
		],
	)

fn show(m: Matches) Void!:
	head := load(m.string("head"))?
	var sources = Map[String, String]()
	for f in head.entities:
		if not sources.contains(f.file):
			sources.add(
				f.file.clone(),
				read_file(
					f"{m.string("sources")}/{f.file}"
				).wait()?.decode_utf8().get_or(""),
			)
	for entry in head.imports:
		if not sources.contains(entry.file):
			sources.add(
				entry.file.clone(),
				read_file(
					f"{m.string("sources")}/{entry.file}"
				).wait()?.decode_utf8().get_or(""),
			)

	var base: Facts? = none
	if path := m.string_or_none("base"): base = load(path)?

	page := files().read("page.html", none).get_or(
		"".to_bytes()
	).decode_utf8().get_or("")
	var out = stdout()
	out.write(html_page(page, head, sources, [], base))?
	out.flush()?
	return ok()

fn main() Int:
	return run_tool(html_tool(), show)

test "type hints share one type table and sort by position":
	var ix = Index(
		files: ["a.ms", "b.ms"],
		file_ix: Map[String, Int](),
		entity_ix: Map[String, Int](),
	)
	ix.file_ix.add("a.ms", 0)
	ix.file_ix.add("b.ms", 1)

	hints := [
		TypeHint(file: "b.ms", line: 0, col: 1, len: 2, ty: "Int"),
		TypeHint(file: "a.ms", line: 3, col: 0, len: 1, ty: "String"),
		TypeHint(file: "a.ms", line: 1, col: 4, len: 3, ty: "Int"),
		TypeHint(file: "c.ms", line: 0, col: 0, len: 1, ty: "Gone"),
	]
	expect_equal(
		render_compact(hints_json(ix, hints)),
		"[[\"Int\",\"String\"],[0,1,4,3,0,0,3,0,1,1,1,0,1,2,0]]",
	)?
