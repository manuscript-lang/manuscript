// The corpus subcommands that read fixtures without running them: `list`, `stats`,
// `lint`.
import (
	parse from "@std/data/json.ms",
	list, read_file, stat from "@std/os/fs.ms",

	Fixture, PHASES, Phase, discover, phase_name, tag_allowed from "./fixture.ms",
	Filter, load_expected, select from "./select.ms",
)

fn tag_list(fx: Fixture) String:
	return fx.tags.join(",")

// One line per selected fixture: id, phase and tags.
export fn list_lines(all: List[Fixture], filter: Filter) List[String]:
	var lines = List[String]()

	for at in select(all, filter):
		fx := all[at]
		lines.append(f"{fx.id}\t{phase_name(fx.phase)}\t{tag_list(fx)}")

	return lines

fn count_row(label: String, total: Int, per_phase: List[Int]) String:
	var row = f"| {label} | {total} |"
	for count in per_phase:
		row += f" {count} |"
	return row

// A markdown table of selected fixtures per tag and phase.
export fn stats_lines(all: List[Fixture], filter: Filter) List[String]:
	selected := select(all, filter)
	var tags = List[String]()
	for at in selected:
		for tag in all[at].tags:
			if not tags.contains(tag): tags.append(tag.clone())

	var rows = List[String]()

	for tag in tags.sorted():
		var per_phase = List[Int]()
		var total = 0

		for phase in PHASES:
			var count = 0
			for at in selected:
				if all[at].phase == phase and all[at].tags.contains(tag): count += 1
			per_phase.append(count)
			total += count

		rows.append(count_row(tag, total, per_phase))

	var out = List[String]()
	out.append(f"{selected.length()} fixtures")

	var header = "| tag | total |"
	for phase in PHASES:
		header += f" {phase_name(phase)} |"
	out.append(header)
	out.append("|---|---:|---:|---:|---:|---:|")

	var overall = List[Int]()

	for phase in PHASES:
		var count = 0
		for at in selected:
			if all[at].phase == phase: count += 1
		overall.append(count)

	out.append(count_row("all", selected.length(), overall))
	for row in rows:
		out.append(row.clone())
	return out

// The `phase` member of the recorded document, as Rust's `{:?}` of an Option prints it.
fn recorded_phase(fx: Fixture) String:
	if data := read_file(fx.expected_path).wait():
		text := data.decode_utf8().get_or("")
		if doc := parse(text):
			if member := doc.get("phase"):
				if value := member.as_string(): return f"Some(\"{value}\")"

	return "None"

fn fixture_problems(fx: Fixture, seen: List[String]) List[String]:
	var problems = List[String]()
	id := fx.id
	if seen.contains(id): problems.append(f"{id}: duplicate id")
	if fx.tags.is_empty(): problems.append(f"{id}: no tags")
	for tag in fx.tags:
		if not tag_allowed(tag): problems.append(f"{id}: unknown tag {tag}")
	if fx.phase == Phase.Parse and fx.is_dir:
		problems.append(f"{id}: parse fixtures must be single files")

	loaded := load_expected(fx)

	if loaded.is_error():
		problems.append(f"{id}: {loaded.err()}")
	else if recorded_phase(fx) != f"Some(\"{phase_name(fx.phase)}\")":
		problems.append(
			f"{id}: expectation phase {recorded_phase(fx)} differs from fixture"
		)

	return problems

fn collect_stray(dir: String, known: List[String], var problems: List[String]) Void:
	entries := list(dir).get_or([]).sorted_by_key(fn e: e.name)

	for entry in entries:
		path := f"{dir}/{entry.name}"

		if entry.directory:
			if stat(path + "/conform.meta").is_ok(): continue

			collect_stray(path, known, problems)
		else if path.ends_with(".expected.json") and not known.contains(path):
			problems.append(f"{path}: expectation without a fixture")

// Problems with fixture metadata and expectation files, then a summary line.
export fn lint_lines(corpus: String) Result[List[String], String]:
	found := discover(corpus)
	var problems = found.warnings.clone()
	var ids = List[String]()
	var expected_files = List[String]()

	for fx in found.fixtures:
		for problem in fixture_problems(fx, ids):
			problems.append(problem.clone())
		ids.append(fx.id.clone())
		expected_files.append(fx.expected_path.clone())

	collect_stray(corpus, expected_files, problems)

	var out = problems.clone()
	out.append(f"{found.fixtures.length()} fixtures, {problems.length()} problems")
	return ok(out)
