// Conformance fixtures: how they are found on disk, their metadata header, and the
// working copy a run is given. A fixture is `<slug>.ms` with `<slug>.expected.json`
// beside it, or a directory holding `conform.meta`, sources and `expected.json`.
import (
	Bytes from "@std/bytes.ms",
	parse from "@std/data/json.ms",
	CopyOptions, copy, create_directory, list, read_file, stat from "@std/os/fs.ms",
)

export enum Phase:
	Parse
	Check
	Run
	Test

export PHASES := [Phase.Parse, Phase.Check, Phase.Run, Phase.Test]

export fn phase_name(phase: Phase) String:
	if phase == Phase.Parse: return "parse"
	if phase == Phase.Check: return "check"
	if phase == Phase.Run: return "run"

	return "test"

export fn phase_from_name(name: String) Phase?:
	for phase in PHASES:
		if phase_name(phase) == name: return phase
	return none

// The position of a phase in `PHASES`, for ordering.
export fn phase_index(phase: Phase) Int:
	for at in 0..PHASES.length():
		if PHASES[at] == phase: return at
	return 0

TAGS := [
	"lexer", "layout", "parser", "formatter", "types", "generics", "interfaces",
	"closures", "match", "destructuring", "try-result", "optional", "scope-cleanup",
	"faults", "strings", "lists", "maps", "sets", "numbers", "decimal", "interpolation",
	"records", "alternatives", "control-flow", "functions", "modules", "projects",
	"diagnostics", "mutation", "json-protocol", "docs", "examples", "perf", "fuzz",
	"bench", "stdlib", "cli", "testing", "aliasing", "tier-core", "tier-stdlib",
	"tier-io"
]

// Whether `tag` is one the corpus allows: a listed one, or `stdlib-<module>`.
export fn tag_allowed(tag: String) Bool:
	if TAGS.contains(tag): return true
	if rest := tag.cut_prefix("stdlib-"): return not rest.is_empty()

	return false

export type Fixture:
	id: String
	// The file, or for a project fixture the directory.
	root: String
	is_dir: Bool
	tags: List[String]
	phase: Phase
	origin: String
	args: List[String]
	stdin: Bytes
	// Seconds, or -1 for the phase's default.
	timeout_secs: Int
	entry: String
	deterministic: Bool
	expected_path: String

PREFIX := "// conform:"
SUPPORT := "support"

// The number of leading `// conform:` lines of a source.
export fn header_length(source: String) Int:
	var count = 0

	for line in source.lines():
		if not line.starts_with(PREFIX): break

		count += 1

	return count

type Meta:
	tags: List[String] = []
	phase: Phase? = none
	origin: String = ""
	args: List[String] = []
	timeout_secs: Int = -1
	entry: String = ""
	deterministic: Bool = false

fn parse_meta(text: String) Result[Meta, String]:
	var meta = Meta()

	for line in text.lines():
		rest := line.cut_prefix(PREFIX).get_or("")

		if not line.starts_with(PREFIX):
			if (
				line.trim().is_empty()
				or line.starts_with("#")
				or line.starts_with("//")
			): continue

			break

		parts := rest.trim().split_once("=").ok_or(f"bad conform line: {line}")?
		value := parts.after.trim()
		key := parts.before.trim()

		if key == "tags":
			meta.tags = value.split(",").map(fn t: t.trim()).filter(
				fn t: not t.is_empty()
			)
		else if key == "phase":
			meta.phase = phase_from_name(value)
			if meta.phase.is_none(): return error(f"unknown phase {value}")
		else if key == "origin":
			meta.origin = value.clone()
		else if key == "args":
			meta.args = parse_args(value)?
		else if key == "timeout":
			meta.timeout_secs = value.parse_int().ok_or("bad timeout")?
		else if key == "entry":
			meta.entry = value.clone()
		else if key == "deterministic":
			meta.deterministic = value == "true"
		else:
			return error(f"unknown conform key {key}")

	return ok(meta)

fn parse_args(value: String) Result[List[String], String]:
	doc := parse(value).map_error(fn e: f"args: {e.message}")?
	items := doc.as_list().ok_or("args must be a JSON array")?
	var out = List[String]()
	for item in items:
		out.append(item.as_string().ok_or("args must be strings")?)
	return ok(out)

fn read_text(path: String) String?:
	if data := read_file(path).wait(): return data.decode_utf8()
	return none

fn id_of(root: String, path: String) String:
	rest := path.cut_prefix(root + "/").get_or(path)
	return rest.cut_suffix(".ms").get_or(rest)

fn finish(
	id: String,
	root: String,
	is_dir: Bool,
	meta: Meta,
	stdin: Bytes,
	expected_path: String,
	default_entry: String,
) Result[Fixture, String]:
	phase := meta.phase.ok_or("missing phase")?
	entry := if meta.entry.is_empty(): default_entry.clone() else: meta.entry.clone()
	if entry.is_empty(): return error("project fixture needs entry= (no ms.toml)")

	return ok(
		Fixture(
			id: id,
			root: root,
			is_dir: is_dir,
			tags: meta.tags.clone(),
			phase: phase,
			origin: meta.origin.clone(),
			args: meta.args.clone(),
			stdin: stdin,
			timeout_secs: meta.timeout_secs,
			entry: entry,
			deterministic: meta.deterministic,
			expected_path: expected_path,
		)
	)

fn read_bytes_or_empty(path: String) Bytes:
	if data := read_file(path).wait(): return data
	return "".to_bytes()

fn load_file(root: String, path: String) Result[Fixture, String]:
	source := read_text(path).ok_or("cannot read as UTF-8 text")?
	meta := parse_meta(source)?
	stem := path.cut_suffix(".ms").get_or(path)
	name := path.split("/").last().get_or(path)
	return finish(
		id_of(root, path),
		path,
		false,
		meta,
		read_bytes_or_empty(stem + ".stdin"),
		stem + ".expected.json",
		name,
	)

fn load_dir(root: String, dir: String) Result[Fixture, String]:
	meta_text := read_text(dir + "/conform.meta").ok_or("cannot read conform.meta")?
	meta := parse_meta(meta_text)?
	has_manifest := stat(dir + "/ms.toml").is_ok()
	return finish(
		id_of(root, dir),
		dir.clone(),
		true,
		meta,
		read_bytes_or_empty(dir + "/conform.stdin"),
		dir + "/expected.json",
		if has_manifest: "ms.toml" else: "",
	)

fn walk(
	root: String,
	dir: String,
	var found: List[Fixture],
	var warnings: List[String],
) Void:
	entries := list(dir).get_or([]).sorted_by_key(fn e: e.name)

	for entry in entries:
		path := f"{dir}/{entry.name}"

		if entry.directory:
			if entry.name == SUPPORT: continue

			if stat(path + "/conform.meta").is_ok():
				add_loaded(load_dir(root, path.clone()), path, found, warnings)
			else:
				walk(root, path, found, warnings)
		else if entry.name.ends_with(".ms"):
			add_loaded(load_file(root, path.clone()), path, found, warnings)

fn add_loaded(
	loaded: Result[Fixture, String],
	path: String,
	var found: List[Fixture],
	var warnings: List[String],
) Void:
	if loaded.is_ok():
		found.append(loaded.get())
	else:
		warnings.append(f"{path}: {loaded.err()}")

export type Discovered:
	fixtures: List[Fixture]
	warnings: List[String]

// Every fixture under `root`, sorted by id, and a warning for each that cannot be
// loaded.
export fn discover(root: String) Discovered:
	var fixtures = List[Fixture]()
	var warnings = List[String]()
	walk(root, root, fixtures, warnings)
	return Discovered(fixtures: fixtures.sorted_by_key(fn f: f.id), warnings: warnings)

// The bytes under a path, for ordering the longest programs first.
export fn weight(fixture: Fixture) Int:
	if not fixture.is_dir:
		if info := stat(fixture.root): return info.size
		return 0

	return tree_size(fixture.root)

fn tree_size(dir: String) Int:
	var total = 0

	for entry in list(dir).get_or([]):
		path := f"{dir}/{entry.name}"

		if entry.directory:
			total += tree_size(path)
		else if info := stat(path):
			total += info.size

	return total

// Copies the fixture into `work` and returns the entry to run. The harness's own files
// stay behind; modules a single-file fixture imports as `./support/<name>.ms` come
// along.
export fn materialize(fixture: Fixture, work: String) Result[String, Error]:
	create_directory(work, recursive: true)?

	if fixture.is_dir:
		copy_tree(fixture.root, work)?
		return ok(fixture.entry.clone())

	name := fixture.root.split("/").last().get_or(fixture.root)
	copy(fixture.root, f"{work}/{name}", CopyOptions(replace: true))?

	parent := fixture.root.rsplit_once("/").map(fn parts: parts.before).get_or(".")
	support := f"{parent}/{SUPPORT}"
	if stat(support).is_ok(): copy_tree(support, f"{work}/{SUPPORT}")?
	return ok(fixture.entry.clone())

HARNESS_FILES := ["conform.meta", "expected.json", "conform.stdin"]

fn copy_tree(from: String, to: String) Result[Void, Error]:
	create_directory(to, recursive: true)?

	for entry in list(from)?:
		if HARNESS_FILES.contains(entry.name): continue

		if entry.directory:
			copy_tree(f"{from}/{entry.name}", f"{to}/{entry.name}")?
		else:
			copy(
				f"{from}/{entry.name}",
				f"{to}/{entry.name}",
				CopyOptions(replace: true),
			)?

	return ok(void)
