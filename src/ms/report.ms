// The review report: fixed templates filled with checker facts; nothing is written by a
// model. Port of crates/ms-tooling/src/report.rs; the Rust code is the oracle
// (`ms-tooling-dev report`, same arguments).
//
//   ms run src/ms/report.ms -- BASE.json HEAD.json [--no-base] [--added FILE]... [--touch FILE:LINE]...
//       [--stats FILES SOURCES INSERTIONS DELETIONS] [--all] [--effect NAME] [--format ascii|markdown|json]
//   ms run src/ms/report.ms -- --project HEAD.json [--all] [--format ...]
import (
	Arg, Command, Flag, FlagKind, Matches from "@std/cli/command.ms",
	sha256 from "@std/crypto/crypto.ms",
	hex_encode from "@std/data/encoding.ms",
	JsonValue, parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	read_file from "@std/os/fs.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	run_tool from "./cli.ms",
	flag, list_of, number, object, render_document, text, with from "./json_out.ms",
	DiffInput, Finding, compare_facts, diff_input from "./review.ms",
	Facts from "./views.ms",
)

// The version of the report template set. Any wording change bumps it, so two reports
// with the same format are comparable.
export REPORT_FORMAT := 2
ROW_CAP := 5

// One numbered report section: a table, plain lines, or both.
export type Section:
	title: String
	headers: List[String] = []
	rows: List[List[String]] = []
	lines: List[String] = []
	more: Int = 0

export type Report:
	format: Int = 2
	mode: String = ""
	input: String = ""
	result: String = ""
	sections: List[Section] = []
	findings: List[Finding] = []
	digest: String = ""
	// Whether semantic comparison succeeded; none for a project map.
	base_checked: Bool? = none

// Selects how much of each section is shown.
export type ReviewOptions:
	all: Bool = false
	// Keep only findings whose effect rows name this effect or match this pattern;
	// empty keeps all.
	effect: String = ""

// How the changed files looked, for the `input` line.
export type DiffStats:
	files: Int = 0
	sources: Int = 0
	insertions: Int = 0
	deletions: Int = 0

type Capped:
	rows: List[List[String]]
	more: Int

fn capped(rows: List[List[String]], options: ReviewOptions) Capped:
	if options.all or rows.length() <= ROW_CAP: return Capped(
		rows: rows.clone(),
		more: 0,
	)
	return Capped(
		rows: rows.slice(0, ROW_CAP).get_or([]),
		more: rows.length() - ROW_CAP,
	)

type CappedLines:
	lines: List[String]
	more: Int

fn cap_lines(lines: List[String], options: ReviewOptions) CappedLines:
	if options.all or lines.length() <= ROW_CAP: return CappedLines(
		lines: lines.clone(),
		more: 0,
	)
	return CappedLines(
		lines: lines.slice(0, ROW_CAP).get_or([]),
		more: lines.length() - ROW_CAP,
	)

fn effect_list(effects: List[String]) String: if effects.is_empty(): "none" else: effects.join(
	"+"
)

fn or_none(text: String) String: if text.is_empty(): "none" else: text.clone()

// Whether `pattern` covers the declared effect `effect`: `*`, `prefix.*`, `*.suffix` or
// an exact name.
export fn effect_matches(pattern: String, effect: String) Bool:
	if pattern == "*": return true

	if pattern.ends_with(".*"):
		prefix := pattern.slice(0, pattern.length() - 2)
		return (
			effect.length() > prefix.length()
			and effect.starts_with(prefix)
			and effect.slice(prefix.length(), prefix.length() + 1) == "."
		)

	if pattern.starts_with("*."):
		suffix := pattern.slice(2, pattern.length())
		parts := effect.split(".")
		return parts.length() > 1 and parts[parts.length() - 1] == suffix

	return pattern == effect

// Whether an effect row of `finding` (`permits: + std.fs.*`,
// `reaches: + std.net.connect`) lists
// `effect`, or a listed name matches `effect` read as a pattern.
fn names_effect(finding: Finding, effect: String) Bool:
	for change in finding.changes:
		var list = ""

		if rest := change.cut_prefix("permits: + "): list = rest.clone()
		else if rest := change.cut_prefix("reaches: + "): list = rest.clone()
		else: continue

		for name in list.split(", "):
			if name == effect or effect_matches(effect, name): return true

	return false

fn count_tier(findings: List[Finding], tier: String) Int:
	var n = 0
	for f in findings:
		if f.tier == tier: n += 1
	return n

fn row(cells: List[String]) List[String]: cells

// Builds the report for a change: head facts, base facts, and input.
export fn diff_report(
	base: Facts,
	head: Facts,
	input: DiffInput,
	stats: DiffStats,
	options: ReviewOptions,
) Report:
	var findings = compare_facts(base, head, input)
	if not options.effect.is_empty(): findings = findings.filter(
		fn f: names_effect(f, options.effect)
	)

	internal := count_tier(findings, "INTERNAL")
	attention := findings.length() - internal
	var r = Report(mode: "diff", base_checked: input.base_checked)
	r.input = f"diff ({stats.files} files, {stats.sources} source, +{stats.insertions} -{stats.deletions})"

	if not input.base_checked: r.result = "base did not check; semantic comparison unavailable"
	else if findings.is_empty(): r.result = "no tracked semantic changes"
	else: r.result = f"{attention} need attention, {internal} internal"

	summary := Section(
		title: "SUMMARY",
		lines: [
			f"changed entities      {findings.length()}",
			f"contract              {count_tier(findings, "CONTRACT")}",
			f"effect                {count_tier(findings, "EFFECT+")}",
			f"error flow            {count_tier(findings, "ERROR")}",
			f"resource              {count_tier(findings, "RESOURCE")}",
			f"internal only         {internal}"
		],
	)
	var rows = List[List[String]]()
	var evidence = List[List[String]]()

	for f in findings:
		if f.tier == "INTERNAL": continue

		rows.append(
			[
				f"{rows.length() + 1}",
				f.tier.clone(),
				f.entity.clone(),
				f.changes.join("; "),
				f"{f.reach}",
				f.location.clone(),
				f"{f.score}",
			]
		)

		var detail = [f"id: {f.id}"]
		for e in f.evidence: detail.append(e.clone())
		detail.append(f"score: {f.terms.join(", ")}")
		evidence.append([f"{rows.length()}", detail.join(" | ")])

	look := capped(rows, options)
	shown_evidence := capped(evidence, options)
	r.sections = [
		summary,
		Section(
			title: "LOOK HERE FIRST",
			headers: [
				"#", "TIER", "ENTITY", "CHANGE", "REACH", "WHERE", "SCORE"
			],
			rows: look.rows,
			more: look.more,
		),
		Section(
			title: "EVIDENCE",
			headers: ["#", "DETAIL"],
			rows: shown_evidence.rows,
		),
		tier_section("EFFECTS", ["effects:"], findings, options),
		tier_section(
			"ERROR FLOW",
			["error type:", "try sites:"],
			findings,
			options,
		),
		tier_section("RESOURCES", ["resource scopes:"], findings, options),
		import_section(base, head),
		internal_section(findings, options),
		limits_section(),
	]
	r.findings = findings
	r.digest = compute_digest(r)
	return r

// Lists entities whose reasons include the tier, including those ranked into other
// tiers, so a section answers its question completely.
fn tier_section(
	title: String,
	prefixes: List[String],
	findings: List[Finding],
	options: ReviewOptions,
) Section:
	var lines = List[String]()
	for f in findings:
		for change in f.changes:
			for p in prefixes:
				if change.starts_with(p): lines.append(f"{f.entity} {change}")

	shown := cap_lines(lines, options)
	return Section(title: title, lines: shown.lines, more: shown.more)

fn sorted_keys(a: Map[String, List[String]], b: Map[String, List[String]]) List[String]:
	var names = Set[String]()
	for k in a.keys(): names.add(k.clone())
	for k in b.keys(): names.add(k.clone())
	return names.values().sorted()

fn import_section(base: Facts, head: Facts) Section:
	old_imports := imports_of(base)
	new_imports := imports_of(head)
	var lines = List[String]()

	for file in sorted_keys(old_imports, new_imports):
		old := old_imports.get(file).get_or([]).to_set()
		now := new_imports.get(file).get_or([]).to_set()
		for path in now.difference(old).values().sorted(): lines.append(
			f"+ {file} imports {path}"
		)
		for path in old.difference(now).values().sorted(): lines.append(
			f"- {file} imports {path}"
		)

	return Section(title: "DEPENDENCIES", lines: lines)

fn imports_of(facts: Facts) Map[String, List[String]]:
	var out = Map[String, List[String]]()
	for entry in facts.imports: out.add(entry.file.clone(), entry.paths.clone())
	return out

fn internal_section(findings: List[Finding], options: ReviewOptions) Section:
	var lines = List[String]()
	for f in findings:
		if f.tier == "INTERNAL": lines.append(f"{f.entity} ({f.changes.join("; ")})")
	lines.sort()

	shown := cap_lines(lines, options)
	return Section(title: "INTERNAL", lines: shown.lines, more: shown.more)

fn limits_section() Section:
	return Section(
		title: "READING THIS REPORT",
		lines: [
			"Static analysis of checked source; tests are not run.",
			"INTERNAL means no tracked contract, effect, error-flow, or resource change; runtime behavior can still change.",
			"Use --explain <number|id> with --diff for evidence and a focused diagram."
		],
	)

fn table_section(
	title: String,
	headers: List[String],
	rows: List[List[String]],
	options: ReviewOptions,
) Section:
	shown := capped(rows, options)
	return Section(title: title, headers: headers, rows: shown.rows, more: shown.more)

fn import_map(head: Facts) Section:
	var lines = List[String]()
	for entry in head.imports.sorted_by_key(fn e: e.file.clone()):
		lines.append(f"{entry.file} imports {or_none(entry.paths.join(", "))}")
	return Section(title: "DEPENDENCIES", lines: lines)

// Describes the head alone: the same template without a diff.
export fn project_report(head: Facts, options: ReviewOptions) Report:
	var r = Report(mode: "project", input: "project (no diff)")
	var exported = 0
	var tests = 0
	var scopes = 0
	var files = Set[String]()

	for f in head.entities:
		if f.exported: exported += 1
		if f.kind == "test": tests += 1
		if f.scopes > 0: scopes += 1
		files.add(f.file.clone())

	for entry in head.imports: files.add(entry.file.clone())
	r.result = f"{files.length()} modules, {head.entities.length()} entities"

	summary := Section(
		title: "SUMMARY",
		lines: [
			f"modules               {files.length()}",
			f"entities              {head.entities.length()}",
			f"exported              {exported}", f"tests                 {tests}",
			f"resource scopes       {scopes}"
		],
	)
	var surface = List[List[String]]()
	var entries = List[List[String]]()
	var resources = List[List[String]]()
	var error_types = Map[String, Int]()

	for f in head.entities:
		at := f"{f.file}:{f.line}"
		if f.exported: surface.append(
			[f.name.clone(), f.kind.clone(), f.ty.clone(), at.clone()]
		)
		if (f.name == "main" and f.exported) or f.kind == "test": entries.append(
			[
				f.name.clone(),
				f.kind.clone(),
				effect_list(f.effects),
				at.clone(),
			]
		)
		if f.scopes > 0: resources.append([f.name.clone(), f"{f.scopes}", at.clone()])
		if not f.error.is_empty(): error_types.add(
			f.error.clone(),
			error_types.get(f.error).get_or(0) + 1,
		)

	var error_rows = List[List[String]]()
	for e in error_types.keys().sorted(): error_rows.append(
		[e.clone(), f"{error_types.get(e).get_or(0)}"]
	)
	r.sections = [
		summary,
		table_section(
			"PUBLIC SURFACE",
			["ENTITY", "KIND", "TYPE", "WHERE"],
			surface,
			options,
		),
		table_section(
			"ENTRY POINTS",
			["ENTITY", "KIND", "EFFECTS", "WHERE"],
			entries,
			options,
		),
		table_section(
			"ERROR TYPES",
			["TYPE", "FUNCTIONS"],
			error_rows,
			options,
		),
		table_section(
			"RESOURCES",
			["ENTITY", "WITH", "WHERE"],
			resources,
			options,
		),
		import_map(head),
		limits_section(),
	]
	r.digest = compute_digest(r)
	return r

// Hashes the ascii body, so equal digests mean equal reports.
fn compute_digest(r: Report) String:
	return f"sha256:{hex_encode(sha256(body(r, "ascii").to_bytes()))}"

fn section_json(s: Section) JsonValue:
	var out = with(object(), "title", text(s.title))
	if not s.headers.is_empty(): out = with(out, "headers", strings(s.headers))

	if not s.rows.is_empty():
		var rows = List[JsonValue]()
		for r in s.rows: rows.append(strings(r))
		out = with(out, "rows", list_of(rows))

	if not s.lines.is_empty(): out = with(out, "lines", strings(s.lines))
	if s.more > 0: out = with(out, "more", number(s.more))
	return out

fn strings(items: List[String]) JsonValue:
	var out = List[JsonValue]()
	for item in items: out.append(text(item))
	return list_of(out)

fn nullable_strings(items: List[String]) JsonValue:
	if items.is_empty(): return JsonValue.Null
	return strings(items)

fn finding_json(f: Finding, rank: JsonValue) JsonValue:
	var out = object()
	out = with(out, "id", text(f.id))
	out = with(out, "tier", text(f.tier))
	out = with(out, "entity", text(f.entity))
	out = with(out, "where", text(f.location))
	out = with(out, "changes", nullable_strings(f.changes))
	out = with(out, "reach", number(f.reach))
	out = with(out, "score", number(f.score))
	out = with(out, "terms", nullable_strings(f.terms))
	if not f.evidence.is_empty(): out = with(out, "evidence", strings(f.evidence))
	return with(out, "number", rank)

fn report_json(r: Report) JsonValue:
	var out = object()
	out = with(out, "format", number(r.format))
	out = with(out, "mode", text(r.mode))
	out = with(out, "input", text(r.input))
	out = with(out, "result", text(r.result))

	if checked := r.base_checked: out = with(out, "base_checked", flag(checked))
	else: out = with(out, "base_checked", JsonValue.Null)

	var sections = List[JsonValue]()
	for s in r.sections: sections.append(section_json(s))
	out = with(out, "sections", list_of(sections))

	var findings = List[JsonValue]()
	var rank = 0

	for f in r.findings:
		if f.tier == "INTERNAL": findings.append(finding_json(f, JsonValue.Null))
		else:
			rank += 1
			findings.append(finding_json(f, number(rank)))

	out = with(out, "findings", list_of(findings))
	return with(out, "digest", text(r.digest))

// Writes the report as ascii, markdown, or json.
export fn render(r: Report, format: String) String:
	if format == "json": return render_document(report_json(r))
	return f"{body(r, format)}\ndigest {r.digest}\n"

fn body(r: Report, format: String) String:
	md := format == "markdown"
	var b = ""

	if md: b = f"# Manuscript review report (format {r.format})\n\n- input: {r.input}\n- result: {r.result}\n"
	else: b = f"MANUSCRIPT REVIEW REPORT  format {r.format}\ninput   {r.input}\nresult  {r.result}\n"

	for i in 0..r.sections.length():
		s := r.sections[i]

		if md: b = b.concat(f"\n## {i + 1}. {s.title}\n\n")
		else: b = b.concat(f"\n{i + 1}. {s.title}\n")

		b = b.concat(section_text(s, md))

	return b.trim_end_chars("\n").concat("\n")

fn indent(md: Bool) String: if md: "- " else: "   "

fn section_text(s: Section, md: Bool) String:
	if s.rows.is_empty() and s.lines.is_empty(): return f"{indent(md)}none\n"

	var b = ""
	if not s.rows.is_empty(): b = table_text(s, md)
	for line in s.lines: b = b.concat(f"{indent(md)}{line}\n")
	if s.more > 0: b = b.concat(f"{indent(md)}+{s.more} more (use --all)\n")
	return b

fn pad(cell: String, width: Int) String: cell.concat(" ".repeat(width - cell.length()))

fn row_text(cells: List[String], widths: List[Int]) String:
	var parts = List[String]()

	for i in 0..cells.length():
		if i + 1 == cells.length(): parts.append(cells[i].clone())
		else: parts.append(pad(cells[i], widths[i]))

	return f"   {parts.join("  ")}\n"

fn table_text(s: Section, md: Bool) String:
	var b = ""

	if md:
		b = f"| {s.headers.join(" | ")} |\n|{" --- |".repeat(s.headers.length())}\n"

		for r in s.rows:
			var cells = List[String]()
			for c in r: cells.append(c.replace("|", "\\|"))
			b = b.concat(f"| {cells.join(" | ")} |\n")

		return b

	// Go pads by byte length, so widths count bytes.
	var widths = List[Int]()
	for h in s.headers: widths.append(h.length())
	for r in s.rows:
		for i in 0..r.length():
			if r[i].length() > widths[i]: widths[i] = r[i].length()
	b = row_text(s.headers, widths)
	for r in s.rows: b = b.concat(row_text(r, widths))
	return b

// ---- Entry ----

fn load(path: String) Facts!:
	return ok(parse[Facts](read_file(path).wait()?.decode_utf8().get_or(""))?)

fn report_tool() Command:
	return Command(
		name: "report.ms",
		about: "Print the review report of a change, or the map of a project",
		args: [
			Arg("first", help: "BASE.json, or HEAD.json with --project"),
			Arg("second", help: "HEAD.json", required: false),
		],
		flags: [
			Flag(
				"project",
				FlagKind.Bool,
				help: "Map one project instead of comparing two",
			),
			Flag(
				"no-base",
				FlagKind.Bool,
				help: "The base was not rebuilt from the diff",
			),
			Flag("all", FlagKind.Bool, help: "Show every row"),
			Flag("effect", help: "Keep findings that reach this effect"),
			Flag("format", help: "ascii, markdown or json"),
			Flag("added", FlagKind.List, help: "A source the change adds"),
			Flag(
				"touch",
				FlagKind.List,
				help: "FILE:LINE a change touches",
			),
			Flag(
				"stats",
				help: "FILES,SOURCES,INSERTIONS,DELETIONS of the diff",
			),
		],
	)

// `--stats FILES,SOURCES,INSERTIONS,DELETIONS`; zeros when absent.
fn diff_stats(m: Matches) DiffStats:
	text := m.string_or_none("stats").get_or("0,0,0,0")
	parts := text.split(",").map(fn part: part.parse_int().get_or(0))
	if parts.length() != 4: return DiffStats()

	return DiffStats(
		files: parts[0],
		sources: parts[1],
		insertions: parts[2],
		deletions: parts[3],
	)

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.console.write
fn show(m: Matches) Void!:
	options := ReviewOptions(
		all: m.bool("all"),
		effect: m.string_or_none("effect").get_or(""),
	)
	format := m.string_or_none("format").get_or("ascii")
	first := load(m.string("first"))?
	var report = Report()

	if m.bool("project"):
		if m.string_or_none("second").is_some(): return error(
			Error("--project takes one facts file")
		)

		report = project_report(first, options)
	else:
		second := m.string_or_none("second")
		if second.is_none(): return error(
			Error("a change needs BASE.json and HEAD.json")
		)

		report = diff_report(
			first,
			load(second.get())?,
			diff_input(m)?,
			diff_stats(m),
			options,
		)

	var out = stdout()
	out.write(render(report, format))?
	out.flush()?
	return ok()

fn main() Int:
	return run_tool(report_tool(), show)
