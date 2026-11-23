// The conformance corpus replayed against an ms binary, in Manuscript. This is the
// runner that replaces the Rust `ms-conform run`: it reads each fixture's recorded
// expectation (<name>.expected.json beside a .ms file, or expected.json in a project
// directory with a conform.meta), observes the ms under test the way
// crates/ms-conform/src/observe.rs does, and counts the fixtures whose observation
// equals the recorded one. The frozen Rust runner stays as the cross-check until both
// give the same counts.
//
// `--record` writes each selected fixture's expectation from the ms under test instead of
// comparing (`--only-missing` keeps recorded ones, `--no-stable-check` skips the second
// observation, `--prune` deletes fixtures that cannot be recorded). Fuzz and harvest
// are not ported (#6225, #6226). MS names the ms under test (default
// .artifacts/build/ci/src/cli/ms). CONFORM_DIFF=1 prints each failure's expected and
// observed (first 600 characters). CONFORM_BUILD_TYPE picks the build type of run and
// test (default Release). Fixtures tagged `aliasing` are left out of check, run and
// test as the gate does (`--exclude-tag aliasing`). Usage: ms run tools/conform-run.ms
// -- [--phase parse|check|run|test] [--jobs N] [fixture id substring ...] Prints
// `<phase>: passed/total` and one `FAIL <id>` line per difference.
import (
	Bytes from "@std/bytes.ms",
	Promise, promise from "@std/concurrency/promise.ms",
	JsonValue, StringifyOptions, parse, stringify from "@std/data/json.ms",
	arguments, environment, working_directory from "@std/os/env.ms",
	CopyOptions,
	GlobOptions,
	access,
	copy,
	create_directory,
	glob,
	read_file,
	remove,
	temporary,
	write_file from "@std/os/fs.ms",
	CommandOutput, RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// A recorded fixture: a single .ms file (with an optional support/ directory beside it)
// or a project directory.
type Fixture:
	id: String
	phase: String
	path: String
	is_dir: Bool
	entry: String
	args: List[String]
	stdin: Bytes
	timeout: Int
	tags: List[String]
	deterministic: Bool
	sidecar: String
	expected: JsonValue

// The `// conform:` header of a fixture.
type Meta:
	tags: List[String]
	phase: String
	args: List[String]
	timeout: Int
	entry: String
	deterministic: Bool

// What one run of ms left: its exit status and streams, as text.
type Process:
	code: Int
	stdout: String
	stderr: String
	timed_out: Bool
	spawn_error: String

fn text_of(data: Bytes) String:
	return (data.decode_utf8() or "").clone()

fn string_member(value: JsonValue, key: String) String:
	if found := value.get(key): return found.as_string() or ""
	return ""

fn parent_length(path: String) Int:
	var at = path.length()

	while at > 0:
		at -= 1

		last := path.slice(at, at + 1)
		if last == "/" or last == "\\": return at

	return 0

// The header lines of `text`: `// conform: key=value`, up to the first line that is not
// a comment or blank.
fn parse_meta(text: String) Meta:
	var meta = Meta(
		tags: [],
		phase: "",
		args: [],
		timeout: 0,
		entry: "",
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
		else if key == "deterministic": meta.deterministic = value == "true"
		else if key == "args":
			if document := parse(value).get_or(JsonValue.Null).as_list():
				for item in document: meta.args.append((item.as_string() or "").clone())

	return meta

fn selected(id: String, filters: List[String]) Bool:
	if filters.is_empty(): return true

	for filter in filters:
		if id.contains(filter): return true
	return false

fn read_text(path: String) String:
	return text_of(read_file(path).wait().get_or("".to_bytes()))

// The recorded fixtures of `phase` under `root`, in id order. A directory named
// `support` holds shared files, not fixtures, and nothing below a project directory is
// a fixture.
fn fixtures(root: String, phase: String, filters: List[String]) List[Fixture]:
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
		if recorded := parse(read_text(sidecar)).get_or(JsonValue.Null).get("expected"):
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
fn under_project(id: String, projects: List[String]) Bool:
	for project in projects:
		if project != "" and id.starts_with(project): return true
	return false

// Copies the fixture's inputs into `work`: a project directory without its harness
// files, or a single file with the support/ directory beside it.
fn materialize(fx: Fixture, work: String) Void:
	if fx.is_dir:
		copy(fx.path.clone(), work.clone(), CopyOptions(recursive: true, replace: true)).get()
		for name in ["conform.meta", "expected.json", "conform.stdin"]:
			void remove(f"{work}/{name}")
		return

	copy(fx.path.clone(), f"{work}/{fx.entry}").get()

	support := f"{fx.path.slice(0, parent_length(fx.path))}/support"
	if access(support, 0).is_ok():
		copy(support, f"{work}/support", CopyOptions(recursive: true, replace: true)).get()

fn default_timeout(phase: String) Int:
	if phase == "parse": return 30
	if phase == "check": return 60
	if phase == "run": return 120

	// The slowest test fixture takes about 15 s (many-tasks); twice that is a hang.
	return 30

fn invoke(
	ms: String,
	fx: Fixture,
	args: List[String],
	work: String,
	input: Bytes,
) Process:
	limit := if fx.timeout > 0: fx.timeout else: default_timeout(fx.phase)
	result := run(
		ms.clone(),
		args,
		RunOptions(
			cwd: work.clone(),
			timeout: seconds(limit),
			input: input,
			env: {"MS_UNDER_TEST": ms.clone()},
		),
	).wait()
	if out := result:
		return Process(
			code: out.exit_code,
			stdout: text_of(out.stdout),
			stderr: text_of(out.stderr),
			timed_out: false,
			spawn_error: "",
		)

	cause := result.err()
	timed := (cause.kind or "") == "ETIMEDOUT"
	return Process(
		code: if timed: 137 else: 127,
		stdout: "",
		stderr: "",
		timed_out: timed,
		spawn_error: if timed: "" else: cause.message.clone(),
	)

// `text` with the work directory (as given and with forward slashes) as <DIR> and its
// parent as <SCRATCH>, and the line number of a standard-library frame as <LINE>.
fn normalize_text(text: String, work: String) String:
	var out = text.replace(work, "<DIR>").replace(work.replace("\\", "/"), "<DIR>")
	parent_end := parent_length(work)

	if parent_end > 0:
		parent := work.slice(0, parent_end)
		out = out.replace(parent, "<SCRATCH>").replace(
			parent.replace("\\", "/"),
			"<SCRATCH>",
		)

	return mask_stdlib_lines(out)

// A standard-library frame (`@std/concurrency/promise.ms:312`) names its line as
// <LINE>, so editing a standard-library file does not change the expectation of every
// fixture that faults through it.
fn mask_stdlib_lines(text: String) String:
	if not text.contains("@std/"): return text.clone()

	var out = ""
	var rest = text.clone()

	while true:
		at := rest.index_of("@std/") or (-1)
		if at < 0: break

		out += rest.slice(0, at)

		tail := rest.slice(at, rest.length())
		dot := tail.index_of(".ms:") or (-1)

		if dot < 0:
			out += tail
			return out

		name := tail.slice(0, dot)
		after := tail.slice(dot + 4, tail.length())
		digits := leading_digits(after)

		if digits > 0 and path_name(name):
			out += tail.slice(0, dot + 4) + "<LINE>"
			rest = after.slice(digits, after.length()).clone()
		else:
			out += "@std/"
			rest = tail.slice(5, tail.length()).clone()

	return out + rest

fn leading_digits(text: String) Int:
	var count = 0
	while count < text.length() and "0123456789".contains(text.slice(count, count + 1)): count += 1
	return count

fn path_name(name: String) Bool:
	for index in 0..name.length():
		letter := name.slice(index, index + 1)
		if not (
			"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@/_-".contains(
				letter
			)
		): return false

	return true

// Every string of `value` normalized, and the `subcode` members the frozen corpus never
// recorded dropped.
fn normalized(value: JsonValue, work: String) JsonValue:
	match value:
		StringValue(text): return JsonValue.StringValue(normalize_text(text, work))
		ArrayValue(items):
			var out = List[JsonValue]()
			for item in items: out.append(normalized(item, work))
			return JsonValue.ArrayValue(out)
		ObjectValue(fields):
			var out = Map[String, JsonValue]()

			for field in fields.entries():
				if field.key == "subcode": continue

				out.add(field.key.clone(), normalized(field.value, work))

			return JsonValue.ObjectValue(out)
		_: return value.clone()

// A JSON report read from standard output and normalized, or a record of why it could
// not be read.
fn read_report(out: Process, work: String) JsonValue:
	parsed := parse(out.stdout)
	if document := parsed: return normalized(document, work)

	var broken = Map[String, JsonValue]()
	broken.add("unparsable_json", JsonValue.StringValue(f"{parsed.err().message}"))
	broken.add("stdout", JsonValue.StringValue(normalize_text(out.stdout, work)))
	return JsonValue.ObjectValue(broken)

fn number(value: Int) JsonValue:
	return JsonValue.NumberValue(f"{value}")

fn text_value(value: String) JsonValue:
	return JsonValue.StringValue(value.clone())

// `exit_code`, `timed_out` and `spawn_error` of a run.
fn process_fields(var fields: Map[String, JsonValue], out: Process) Void:
	fields.add("exit_code", number(out.code))
	if out.timed_out: fields.add("timed_out", JsonValue.BoolValue(true))
	if out.spawn_error != "": fields.add("spawn_error", text_value(out.spawn_error))

// The text of `source` below its `// conform:` header lines.
fn without_header(source: String) String:
	var skip = 0

	for line in source.split("\n"):
		if not line.starts_with("// conform:"): break

		skip += line.length() + 1

	if skip > source.length(): return ""

	return source.slice(skip, source.length())

fn parse_phase(ms: String, fx: Fixture, work: String) JsonValue:
	// `fmt --check` parses without loading the standard library, which `check` does for
	// every file that parses; the parse diagnostics are the same.
	checked := invoke(
		ms,
		fx,
		["fmt", fx.entry.clone(), "--check", "--json"],
		work,
		"".to_bytes(),
	)
	report := read_report(checked, work)
	var diagnostics = List[JsonValue]()
	if listed := report.get("diagnostics"):
		for item in (listed.as_list() or []):
			if string_member(item, "phase") == "parse": diagnostics.append(item.clone())

	var fields = Map[String, JsonValue]()
	fields.add("diagnostics", JsonValue.ArrayValue(diagnostics))
	if report.get("unparsable_json") != null: fields.add("raw", report)

	formatted := invoke(ms, fx, ["fmt", fx.entry.clone()], work, "".to_bytes())

	if formatted.code == 0:
		after := read_text(f"{work}/{fx.entry}")
		fields.add("fmt", text_value(without_header(after)))
	else:
		fields.add("fmt", JsonValue.Null)
		fields.add("fmt_exit_code", number(formatted.code))

	return JsonValue.ObjectValue(fields)

fn check_phase(ms: String, fx: Fixture, work: String) JsonValue:
	// `--with-text` carries the terminal output in the same document. A run that wrote no
	// document, such as a usage error, is repeated without `--json` for its terminal
	// output.
	json_run := invoke(
		ms,
		fx,
		["check", fx.entry.clone(), "--json", "--with-text"],
		work,
		"".to_bytes(),
	)
	report := read_report(json_run, work)
	var text_code = json_run.code
	var stdout = ""
	var stderr = ""

	if text := report.get("text"):
		stdout = string_member(text, "stdout")
		stderr = string_member(text, "stderr")
	else:
		plain := invoke(ms, fx, ["check", fx.entry.clone()], work, "".to_bytes())
		text_code = plain.code
		stdout = normalize_text(plain.stdout, work)
		stderr = normalize_text(plain.stderr, work)

	var fields = Map[String, JsonValue]()
	process_fields(fields, json_run)
	if format := report.get("format"): fields.add("format", format.clone())

	if listed := report.get("diagnostics"): fields.add("diagnostics", listed.clone())
	else: fields.add("diagnostics", JsonValue.ArrayValue([]))

	if report.get("unparsable_json") != null: fields.add("raw", report)

	var text = Map[String, JsonValue]()
	text.add("exit_code", number(text_code))
	text.add("stdout", text_value(stdout))
	text.add("stderr", text_value(stderr))
	fields.add("text", JsonValue.ObjectValue(text))
	return JsonValue.ObjectValue(fields)

fn run_phase(ms: String, fx: Fixture, work: String, build_type: String) JsonValue:
	var args = ["run", fx.entry.clone(), "--build-type", build_type.clone()]

	if not fx.args.is_empty():
		args.append("--")
		for word in fx.args: args.append(word.clone())

	out := invoke(ms, fx, args, work, fx.stdin.clone())
	var fields = Map[String, JsonValue]()
	process_fields(fields, out)
	fields.add("stdout", text_value(normalize_text(out.stdout, work)))
	fields.add("stderr", text_value(normalize_text(out.stderr, work)))
	return JsonValue.ObjectValue(fields)

// `value` without the members called `name`, at every depth.
fn without_member(value: JsonValue, name: String) JsonValue:
	match value:
		ArrayValue(items):
			var out = List[JsonValue]()
			for item in items: out.append(without_member(item, name))
			return JsonValue.ArrayValue(out)
		ObjectValue(fields):
			var out = Map[String, JsonValue]()

			for field in fields.entries():
				if field.key == name: continue

				out.add(field.key.clone(), without_member(field.value, name))

			return JsonValue.ObjectValue(out)
		_: return value.clone()

// The key paths of a report, so a missing or extra field is a protocol break.
fn shape(value: JsonValue, path: String, var out: List[String]) Void:
	match value:
		ObjectValue(fields):
			for field in fields.entries():
				next := if path == "": field.key.clone() else: f"{path}.{field.key}"
				if not out.contains(next): out.append(next.clone())
				shape(field.value, next, out)
		ArrayValue(items):
			for item in items: shape(item, f"{path}[]", out)
		_: return

fn test_phase(ms: String, fx: Fixture, work: String, build_type: String) JsonValue:
	var args = ["test", fx.entry.clone(), "--json", "--build-type", build_type.clone()]

	if not fx.args.is_empty():
		args.append("--")
		for word in fx.args: args.append(word.clone())

	out := invoke(ms, fx, args, work, fx.stdin.clone())

	// The structured `fault` beside a failure text, and the durations, are not
	// recorded.
	faultless := without_member(read_report(out, work), "fault")
	var keys = List[String]()
	shape(faultless, "", keys)
	keys.sort()

	var listed = List[JsonValue]()
	for key in keys: listed.append(text_value(key))

	var fields = Map[String, JsonValue]()
	process_fields(fields, out)
	fields.add("report", without_member(faultless, "duration_ns"))
	fields.add("shape", JsonValue.ArrayValue(listed))
	fields.add("stderr", text_value(normalize_text(out.stderr, work)))
	return JsonValue.ObjectValue(fields)

// What `ms` observes of `fx`, in a fresh working directory.
fn observe(ms: String, fx: Fixture, build_type: String) JsonValue:
	scratch := temporary("ms-conform-").get()
	work := f"{scratch.path()}/w"
	create_directory(work.clone()).get()
	materialize(fx, work.clone())
	if fx.phase == "parse": return parse_phase(ms, fx, work.clone())
	if fx.phase == "check": return check_phase(ms, fx, work.clone())
	if fx.phase == "run": return run_phase(ms, fx, work.clone(), build_type)

	return test_phase(ms, fx, work.clone(), build_type)

fn same(left: JsonValue, right: JsonValue) Bool:
	return stringify(left).get() == stringify(right).get()

// Observes each fixture of `chunk`: one `ok` or `FAIL <id>` line apiece.
fn sweep(
	ms: String,
	build_type: String,
	chunk: List[Fixture],
	detail: Bool,
) List[String]:
	var lines = List[String]()

	for fx in chunk:
		observed := observe(ms, fx, build_type)

		if same(fx.expected, observed): lines.append("ok")
		else if detail: lines.append(
			f"FAIL {fx.id}\n  expected: {clipped(fx.expected)}\n  observed: {clipped(observed)}"
		)
		else: lines.append(f"FAIL {fx.id}")

	return lines

// The first 600 characters of a value, for `CONFORM_DIFF=1` failure reports.
fn clipped(value: JsonValue) String:
	text := stringify(value).get()
	if text.length() <= 600: return text.clone()

	return f"{text.slice(0, 600)}..."

// The text of `ms version`, stored in each expectation for provenance.
fn oracle_version(ms: String) String:
	result := run(ms, ["version"], RunOptions(timeout: seconds(30))).wait()
	if out := result: return text_of(out.stdout).trim().clone()

	return ""

// Why `observed` cannot be recorded, or "".
fn unrecordable(observed: JsonValue) String:
	for key in ["harness_error", "spawn_error", "timed_out", "unparsable_json"]:
		if observed.get(key) != null: return f"observation has {key}"
	if report := observed.get("report"):
		if report.get("unparsable_json") != null: return "ms test did not print JSON"
	return ""

// Records each fixture of `chunk`: one `wrote`, `same`, `kept` or `REJECT <id>: <why>`
// line apiece.
fn record_chunk(
	ms: String,
	build_type: String,
	chunk: List[Fixture],
	version: String,
	stable: Bool,
	only_missing: Bool,
	prune: Bool,
) List[String]:
	var lines = List[String]()

	for fx in chunk:
		if only_missing and access(fx.sidecar, 0).is_ok():
			lines.append("kept")
			continue

		first := observe(ms, fx, build_type)
		why := unrecordable(first)
		var rejected = why
		if rejected == "" and stable and not fx.deterministic:
			if not same(first, observe(ms, fx, build_type)): rejected = "unstable between runs"

		if rejected != "":
			if prune: void remove(fx.path, recursive: true)
			if prune and not fx.is_dir: void remove(fx.sidecar)
			lines.append(f"REJECT {fx.id}: {rejected}")
			continue

		var document = Map[String, JsonValue]()
		document.add("format", number(1))
		document.add("phase", text_value(fx.phase))
		document.add("oracle", text_value(version))
		document.add("expected", first)

		text := (
			stringify(
				JsonValue.ObjectValue(document),
				StringifyOptions(indent: 2),
			).get()
			+ "\n"
		)

		if read_text(fx.sidecar) == text:
			lines.append("same")
			continue

		write_file(fx.sidecar, text, replace: true).wait().get()
		lines.append("wrote")

	return lines

fn main() Int:
	root := working_directory().get()
	var phase = "parse"
	var jobs = 8
	var recording = false
	var only_missing = false
	var stable = true
	var prune = false
	var filters = List[String]()
	var words = List[String]()
	for word in arguments(): words.append(word.clone())

	var at = 0

	while at < words.length():
		if words[at] == "--phase":
			at += 1
			phase = words[at].clone()
		else if words[at] == "--jobs":
			at += 1
			jobs = words[at].parse_int() or 8
		else if words[at] == "--record": recording = true
		else if words[at] == "--only-missing": only_missing = true
		else if words[at] == "--no-stable-check": stable = false
		else if words[at] == "--prune": prune = true
		else: filters.append(words[at].clone())

		at += 1

	if phase != "parse" and phase != "check" and phase != "run" and phase != "test":
		print(f"conform-run: unknown phase {phase}")
		return 64

	ms := tool_ms(root.clone())
	var build_type = "Release"
	if configured := environment().get_or(
		Map[String, String]()
	).get("CONFORM_BUILD_TYPE"): build_type = configured.clone()

	show_diff := environment().get_or(Map[String, String]()).get("CONFORM_DIFF") != null
	var chosen = List[Fixture]()

	for fx in fixtures(f"{root}/tests/conformance/fixtures", phase, filters):
		if phase != "parse" and fx.tags.contains("aliasing"): continue

		chosen.append(fx.clone())

	var jobs_count = jobs
	if jobs_count < 1: jobs_count = 1

	// A promise reads its captures until it is dropped, so the chunks outlive the loop
	// that starts them.
	var chunks = List[List[Fixture]]()

	for worker in 0..jobs_count:
		var mine = List[Fixture]()
		for index in 0..chosen.length():
			if index % jobs_count == worker: mine.append(chosen[index].clone())
		chunks.append(mine)

	if recording:
		version := oracle_version(ms.clone())

		// A promise keeps what it captures, so each one gets its own copies.
		stable_now := stable
		only_missing_now := only_missing
		prune_now := prune
		var recorders = List[Promise[List[String]]]()

		for worker in 0..jobs_count:
			tool := ms.clone()
			kind := build_type.clone()
			mine := chunks[worker].clone()
			release := version.clone()
			recorders.append(
				promise(
					fn: ok(
						record_chunk(
							tool,
							kind,
							mine,
							release,
							stable_now,
							only_missing_now,
							prune_now,
						)
					)
				)
			)

		var counts = Map[String, Int]()

		for task in recorders:
			for line in task.wait().get_or(List[String]()):
				if line.starts_with("REJECT"):
					print(line)
					counts.add("rejected", (counts.get("rejected") or 0) + 1)
				else: counts.add(line.clone(), (counts.get(line) or 0) + 1)

		print(
			f"{phase}: wrote {(counts.get("wrote") or 0)}, same {(counts.get("same") or 0)}, kept {(counts.get("kept") or 0)}, rejected {(counts.get("rejected") or 0)}"
		)
		if (counts.get("rejected") or 0) > 0: return 1

		return 0

	var tasks = List[Promise[List[String]]]()

	for worker in 0..jobs_count:
		tool := ms.clone()
		kind := build_type.clone()
		mine := chunks[worker].clone()
		detail := show_diff
		tasks.append(promise(fn: ok(sweep(tool, kind, mine, detail))))

	var passed = 0

	for task in tasks:
		for line in task.wait().get_or(List[String]()):
			if line == "ok": passed += 1
			else: print(line)

	print(f"{phase}: {passed}/{chosen.length()}")
	if passed != chosen.length(): return 1

	return 0
