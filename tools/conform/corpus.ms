// The conformance corpus on disk: fixture discovery and the `// conform:` metadata,
// shared by the runner (tools/conform-run.ms) and the corpus commands
// (tools/conform.ms).
import (
	Bytes from "@std/bytes.ms",
	JsonValue, parse, stringify from "@std/data/json.ms",
	CopyOptions,
	GlobOptions,
	access,
	copy,
	glob,
	read_file,
	remove from "@std/os/fs.ms",
)

// A recorded fixture: a single .ms file (with an optional support/ directory beside it)
// or a project directory.
export type Fixture:
	id String
	phase String
	path String
	is_dir Bool
	entry String
	args List[String]
	stdin Bytes
	timeout Int
	tags List[String]
	deterministic Bool
	sidecar String
	expected JsonValue

// The `// conform:` header of a fixture.
export type Meta:
	tags List[String]
	phase String
	args List[String]
	timeout Int
	entry String
	origin String
	deterministic Bool

export fn text_of(data Bytes) String:
	return (data.decode_utf8() or "").clone()

export fn string_member(value JsonValue, key String) String:
	found := value.get(key)
	if found != null: return found.as_string() or ""

	return ""

export fn parent_length(path String) Int:
	var at = path.length()

	while at > 0:
		at -= 1

		last := path.slice(at, at + 1)
		if last == "/" or last == "\\": return at

	return 0

// The header lines of `text`: `// conform: key=value`, up to the first line that is not
// a comment or blank.
export fn parse_meta(text String) Meta:
	var meta = Meta(
		tags: [],
		phase: "",
		args: [],
		timeout: 0,
		entry: "",
		origin: "",
		deterministic: false,
	)

	for line in text.split("\n"):
		trimmed := line.trim()
		if trimmed == "" or trimmed.starts_with("#"): continue

		if not trimmed.starts_with("// conform:"):
			if trimmed.starts_with("//"): continue

			break

		rest := trimmed.slice("// conform:".length(), trimmed.length()).trim()
		at := rest.index_of("=") or (-1)
		if at < 0: continue

		key := rest.slice(0, at).trim()
		value := rest.slice(at + 1, rest.length()).trim()

		if key == "tags":
			for tag in value.split(","):
				if tag.trim() != "": meta.tags.append(tag.trim().clone())
		else if key == "phase": meta.phase = value.clone()
		else if key == "timeout": meta.timeout = value.parse_int() or 0
		else if key == "entry": meta.entry = value.clone()
		else if key == "origin": meta.origin = value.clone()
		else if key == "deterministic": meta.deterministic = value == "true"
		else if key == "args":
			document := parse(value).get_or(JsonValue.Null).as_list()
			if document != null:
				for item in document: meta.args.append((item.as_string() or "").clone())

	return meta

export fn selected(id String, filters List[String]) Bool:
	if filters.is_empty(): return true

	for filter in filters:
		if id.contains(filter): return true
	return false

export fn read_text(path String) String:
	return text_of(read_file(path).wait().get_or("".to_bytes()))

// The recorded fixtures of `phase` under `root`, in id order. A directory named
// `support` holds shared files, not fixtures, and nothing below a project directory is
// a fixture.
export fn fixtures(root String, phase String, filters List[String]) List[Fixture]:
	var found = List[Fixture]()
	var projects = List[String]()
	for entry in glob(root, GlobOptions(patterns: ["**/conform.meta"])).get_or([]):
		projects.append(
			entry.path.slice(
				0,
				entry.path.length() - "conform.meta".length(),
			).clone()
		)

	var candidates = List[String]()

	for entry in glob(root, GlobOptions(patterns: ["**/*.ms", "**/conform.meta"])).get_or(
		[]
	):
		if entry.path.contains("/support/") or entry.path.starts_with("support/"): continue

		candidates.append(entry.path.clone())

	candidates.sort()

	for candidate in candidates:
		var id = ""
		var is_dir = false

		if candidate.ends_with("conform.meta"):
			id = candidate.slice(
				0,
				candidate.length() - "/conform.meta".length(),
			).clone()
			is_dir = true
		else:
			id = candidate.slice(0, candidate.length() - ".ms".length()).clone()
			if under_project(id, projects): continue

		if not selected(id, filters): continue

		path := if is_dir: f"{root}/{id}" else: f"{root}/{id}.ms"
		var meta = parse_meta(
			read_text(if is_dir: f"{path}/conform.meta" else: path.clone())
		)
		if meta.phase != phase: continue

		sidecar := if is_dir: f"{path}/expected.json" else: f"{root}/{id}.expected.json"
		var expected = JsonValue.Null
		recorded := parse(read_text(sidecar)).get_or(JsonValue.Null).get("expected")
		if recorded != null:
			expected = recorded.clone()

		if meta.entry == "":
			if is_dir:
				if access(f"{path}/ms.toml", 0).is_ok(): meta.entry = "ms.toml"
			else: meta.entry = id.slice(parent_length(id) + 1, id.length()) + ".ms"

		var stdin = "".to_bytes()
		stdin_path := if is_dir: f"{path}/conform.stdin" else: f"{root}/{id}.stdin"
		if access(stdin_path, 0).is_ok(): stdin = read_file(stdin_path).wait().get()
		found.append(
			Fixture(
				id: id.clone(),
				phase: phase.clone(),
				path: path.clone(),
				is_dir: is_dir,
				entry: meta.entry.clone(),
				args: meta.args.clone(),
				stdin: stdin,
				timeout: meta.timeout,
				tags: meta.tags.clone(),
				deterministic: meta.deterministic,
				sidecar: sidecar.clone(),
				expected: expected.clone(),
			)
		)

	return found

// True when `id` names something below a project directory (ids and `projects` entries
// are `/`-separated, each project ending in `/`).
export fn under_project(id String, projects List[String]) Bool:
	for project in projects:
		if project != "" and id.starts_with(project): return true
	return false

// Copies the fixture's inputs into `work`: a project directory without its harness
// files, or a single file with the support/ directory beside it.
export fn materialize(fx Fixture, work String) Void:
	if fx.is_dir:
		copy(fx.path.clone(), work.clone(), CopyOptions(recursive: true, replace: true)).get()
		for name in ["conform.meta", "expected.json", "conform.stdin"]:
			void remove(f"{work}/{name}")
		return

	copy(fx.path.clone(), f"{work}/{fx.entry}").get()

	support := f"{fx.path.slice(0, parent_length(fx.path))}/support"
	if access(support, 0).is_ok():
		copy(support, f"{work}/support", CopyOptions(recursive: true, replace: true)).get()

// The `// conform:` header lines of `meta`, as `parse_meta` reads them.
export fn render_meta(meta Meta) String:
	var out = f"// conform: tags={meta.tags.join(",")}\n"
	if meta.phase != "": out += f"// conform: phase={meta.phase}\n"
	if meta.origin != "": out += f"// conform: origin={meta.origin}\n"

	if not meta.args.is_empty():
		var items = List[JsonValue]()
		for arg in meta.args: items.append(JsonValue.StringValue(arg.clone()))
		out += f"// conform: args={stringify(JsonValue.ArrayValue(items)).get()}\n"

	if meta.timeout > 0: out += f"// conform: timeout={meta.timeout}\n"
	if meta.entry != "": out += f"// conform: entry={meta.entry}\n"
	if meta.deterministic: out += "// conform: deterministic=true\n"
	return out

// The ids of every fixture under `root`, whatever its phase header says: a `.ms` file
// outside
// `support/` directories and outside project directories, or a project directory.
export fn candidate_ids(root String) List[String]:
	var projects = List[String]()
	for entry in glob(root, GlobOptions(patterns: ["**/conform.meta"])).get_or([]):
		projects.append(
			entry.path.slice(
				0,
				entry.path.length() - "conform.meta".length(),
			).clone()
		)

	var ids = List[String]()

	for entry in glob(root, GlobOptions(patterns: ["**/*.ms", "**/conform.meta"])).get_or(
		[]
	):
		if entry.path.contains("/support/") or entry.path.starts_with("support/"): continue

		if entry.path.ends_with("conform.meta"):
			ids.append(
				entry.path.slice(
					0,
					entry.path.length() - "/conform.meta".length(),
				).clone()
			)
			continue

		id := entry.path.slice(0, entry.path.length() - ".ms".length())
		if not under_project(id, projects): ids.append(id.clone())

	ids.sort()
	return ids
