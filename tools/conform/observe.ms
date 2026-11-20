// Running one fixture against an `ms` binary and reducing what happened to a normalized
// JSON observation. Recording stores an observation; checking compares a fresh one with
// the stored one.
import (
	Bytes from "@std/bytes.ms",
	JsonValue from "@std/data/json.ms",
	min from "@std/math/math.ms",
	canonicalize, list, read_file, remove from "@std/os/fs.ms",
	Duration from "@std/time.ms",

	Output, deadline, execute from "./exec.ms",
	Fixture, Phase, header_length, materialize from "./fixture.ms",
	bool_member,
	flag,
	list_of,
	map_strings,
	number,
	object,
	parse_text,
	shape,
	string_member,
	strings_of,
	text,
	with,
	without_key from "./json_util.ms",
)

// Settings shared by every observation in one invocation.
export type Ctx:
	ms: String
	scratch: String
	// Multiplies every timeout (slow machines, debug builds).
	timeout_scale: Float = 1.0
	env: Map[String, String] = Map[String, String]()
	// `CONFORM_LEAKS` is set: programs run against the runtime that counts live heap blocks, its
	// count line is removed from stderr, and a program of the leak-checked fixture
	// directories that exits with live blocks records `leaked_blocks`.
	leaks: Bool = false
	// The profile `ms run` and `ms test` build with.
	build_type: String = "Release"

// Fixture directories whose programs must free every block they allocate.
LEAK_CHECKED := ["fuzz/run/", "e2e/", "examples/"]
LIVE_BLOCKS := "ms-rt live blocks at exit: "
COUNTS := "ms-rt counts: "
LIVE_BY_SIZE := "ms-rt live blocks by size: "
RUST_HEAP := "ms-rt rust heap at exit: "

type LiveSplit:
	kept: String
	live: Int

// `content` without the counting runtime's lines, and the sum of the live counts.
fn split_live_blocks(content: String) LiveSplit:
	var kept = ""
	var live = 0

	for line in content.split_after("\n"):
		trimmed := line.trim_end()

		if count := trimmed.cut_prefix(LIVE_BLOCKS):
			live += count.trim().parse_int().get_or(0)
		else if not (
			trimmed.starts_with(COUNTS)
			or trimmed.starts_with(LIVE_BY_SIZE)
			or trimmed.starts_with(RUST_HEAP)
		):
			kept += line

	return LiveSplit(kept: kept, live: live)

// Default timeouts in seconds; a first `ms run` may also build the toolchain cache.
fn default_timeout(phase: Phase) Int:
	if phase == Phase.Parse: return 30
	if phase == Phase.Check: return 60
	if phase == Phase.Run: return 120

	return 180

fn Ctx.timeout(fx: Fixture) Duration:
	seconds := if fx.timeout_secs >= 0: fx.timeout_secs else: default_timeout(fx.phase)
	return deadline(seconds.to_float() * self.timeout_scale)

fn Ctx.invoke_within(
	timeout: Duration,
	arguments: List[String],
	cwd: String,
	stdin: Bytes,
) Output:
	return execute(
		self.ms.clone(),
		arguments,
		cwd.clone(),
		stdin.clone(),
		timeout,
		self.env.clone(),
	)

fn Ctx.invoke(fx: Fixture, arguments: List[String], cwd: String, stdin: Bytes) Output:
	return self.invoke_within(self.timeout(fx), arguments, cwd.clone(), stdin.clone())

fn is_name_byte(byte: UInt8) Bool:
	alnum := (
		(byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or (byte >= 97 and byte <= 122)
	)
	return alnum or byte == 64 or byte == 47 or byte == 95 or byte == 45

fn is_digit_byte(byte: UInt8) Bool: byte >= 48 and byte <= 57

fn is_name(content: String) Bool:
	data := content.as_bytes()
	for at in 0..data.length():
		if not is_name_byte(data.get(at)): return false
	return true

// Replaces the line of a standard-library frame (`@std/concurrency/promise.ms:312`)
// with `<LINE>`, so editing a standard-library file does not change the expectation of
// every fixture that faults through it.
fn mask_stdlib_lines(content: String) String:
	var out = ""
	var rest = content.clone()

	while true:
		start := rest.index_of("@std/")
		if start.is_none(): break

		at := start.get()
		out += rest.slice(0, at)

		tail := rest.slice(at, rest.length())
		marker := tail.index_of(".ms:")

		if marker.is_none():
			out += tail
			return out

		dot := marker.get()
		after := tail.slice(dot + 4, tail.length())
		var digits = 0
		while digits < after.length() and is_digit_byte(after.as_bytes().get(digits)):
			digits += 1

		if is_name(tail.slice(0, dot)) and digits > 0:
			out += tail.slice(0, dot + 4) + "<LINE>"
			rest = after.slice(digits, after.length())
		else:
			out += "@std/"
			rest = tail.slice(5, tail.length())

	return out + rest

// Every spelling of `path` in `content`: as given, canonical (`/private/var/...` for
// `/var/...`,
// `\\?\C:\...` on Windows), and with `/` separators, which `ms` prints on Windows.
fn replace_spellings(content: String, path: String, with_text: String) String:
	var spellings = [path.clone()]

	if real := canonicalize(path):
		spellings.append(real.cut_prefix("\\\\?\\").get_or(real))
		spellings.append(real.clone())

	var slashed = List[String]()
	for spelling in spellings:
		slashed.append(spelling.replace("\\", "/"))
	spellings = spellings.concat(slashed)

	// The longer spelling goes first: a canonical one can extend the plain one.
	ordered := spellings.distinct().sorted_by_key(fn s: 0 - s.length())
	var out = content.clone()
	for spelling in ordered:
		out = out.replace(spelling, with_text)
	return out

// `content` with the work directory spelled `<DIR>` and its parent `<SCRATCH>`.
export fn normalize_text(content: String, work: String) String:
	var out = replace_spellings(content, work, "<DIR>")

	// Imports such as `../a.ms` name the scratch root, whose name carries a process id.
	if parts := work.rsplit_once("/"):
		out = replace_spellings(out, parts.before, "<SCRATCH>")
	return mask_stdlib_lines(out)

fn process_fields(members: JsonValue, out: Output) JsonValue:
	var o = with(members, "exit_code", number(out.code))
	if out.timed_out: o = with(o, "timed_out", flag(true))
	if not out.spawn_error.is_empty(): o = with(o, "spawn_error", text(out.spawn_error))
	return o

// Records the process's stderr, without the runtime's live-block lines when
// `ctx.leaks`, and
// `leaked_blocks` when a leak-checked fixture left any.
fn set_stderr(
	ctx: Ctx,
	fx: Fixture,
	out: Output,
	members: JsonValue,
	work: String,
) JsonValue:
	var o = members.clone()
	var stderr = out.stderr.clone()

	if ctx.leaks:
		split := split_live_blocks(stderr)
		stderr = split.kept.clone()
		if split.live != 0 and LEAK_CHECKED.any(fn d: fx.id.starts_with(d)):
			o = with(o, "leaked_blocks", number(split.live))

	return with(o, "stderr", text(normalize_text(stderr, work)))

fn normalized(document: JsonValue, work: String) JsonValue:
	// `subcode` was added to the JSON output after the corpus was recorded; the frozen
	// expectations compare without it.
	return without_key(map_strings(document, fn s: normalize_text(s, work)), "subcode")

// The document `ms` printed, normalized; or an `unparsable_json` object when it printed
// none.
fn parse_json_output(out: Output, work: String) JsonValue:
	parsed := parse_text(out.stdout)
	if parsed.is_ok(): return normalized(parsed.get(), work)

	var o = with(object(), "unparsable_json", text(parsed.err()))
	return with(o, "stdout", text(normalize_text(out.stdout, work)))

fn diagnostics_of(report: JsonValue) JsonValue:
	if found := report.get("diagnostics"): return found.clone()
	return list_of([])

fn is_unparsable(report: JsonValue) Bool:
	return report.get("unparsable_json").is_some()

fn run_phase(ctx: Ctx, fx: Fixture, work: String, entry: String) JsonValue:
	var arguments = ["run", entry.clone(), "--build-type", ctx.build_type.clone()]

	if not fx.args.is_empty():
		arguments.append("--")
		arguments = arguments.concat(fx.args)

	out := ctx.invoke(fx, arguments, work, fx.stdin)
	var o = process_fields(object(), out)
	o = with(o, "stdout", text(normalize_text(out.stdout, work)))
	return set_stderr(ctx, fx, out, o, work)

fn text_field(document: JsonValue, stream: String) String:
	if found := document.get(stream): return found.as_string().get_or("")
	return ""

// The check observation: the JSON report (normalized) beside the terminal output
// (normalized).
fn check_observation(
	report: JsonValue,
	json_out: Output,
	text_code: Int,
	stdout: String,
	stderr: String,
) JsonValue:
	var o = process_fields(object(), json_out)
	if format := report.get("format"): o = with(o, "format", format.clone())
	o = with(o, "diagnostics", diagnostics_of(report))
	if is_unparsable(report): o = with(o, "raw", report.clone())

	var terminal = with(object(), "exit_code", number(text_code))
	terminal = with(terminal, "stdout", text(stdout))
	terminal = with(terminal, "stderr", text(stderr))
	return with(o, "text", terminal)

fn check_phase(ctx: Ctx, fx: Fixture, work: String, entry: String) JsonValue:
	// `--with-text` carries the terminal output in the same document, so one `ms check` (and one
	// standard-library load) observes both. A run that wrote no document, such as a
	// usage error, is repeated without `--json` for its terminal output.
	empty := "".to_bytes()
	json_out := ctx.invoke(
		fx,
		["check", entry.clone(), "--json", "--with-text"],
		work,
		empty.clone(),
	)
	report := parse_json_output(json_out, work)
	if terminal := report.get("text"):
		return check_observation(
			report.clone(),
			json_out,
			json_out.code,
			normalize_text(text_field(terminal, "stdout"), work),
			normalize_text(text_field(terminal, "stderr"), work),
		)

	text_out := ctx.invoke(fx, ["check", entry.clone()], work, empty)
	return check_observation(
		report,
		json_out,
		text_out.code,
		normalize_text(text_out.stdout, work),
		normalize_text(text_out.stderr, work),
	)

fn parse_phase(ctx: Ctx, fx: Fixture, work: String, entry: String) JsonValue:
	// `fmt --check` parses without loading and checking the standard library, which `check`
	// does for every file that parses; the parse diagnostics are the same.
	empty := "".to_bytes()
	json_out := ctx.invoke(
		fx,
		["fmt", entry.clone(), "--check", "--json"],
		work,
		empty.clone(),
	)
	report := parse_json_output(json_out, work)
	var parse_diagnostics = List[JsonValue]()
	if items := diagnostics_of(report).as_list():
		for item in items:
			if phase := item.get("phase"):
				if phase.as_string().get_or("") == "parse": parse_diagnostics.append(
					item.clone()
				)

	var o = with(object(), "diagnostics", list_of(parse_diagnostics))
	if is_unparsable(report): o = with(o, "raw", report.clone())

	fmt_out := ctx.invoke(fx, ["fmt", entry.clone()], work, empty)

	if fmt_out.code == 0:
		formatted := read_file(f"{work}/{entry}").wait().get_or(
			"".to_bytes()
		).decode_utf8().get_or("")

		// The metadata header is a comment block at the top; retagging must not move
		// expectations.
		var skip = 0
		for line in formatted.lines().take(header_length(formatted)):
			skip += line.length() + 1
		o = with(
			o,
			"fmt",
			text(
				formatted.slice(
					min(skip, formatted.length()),
					formatted.length(),
				)
			),
		)
	else:
		o = with(o, "fmt", JsonValue.Null)
		o = with(o, "fmt_exit_code", number(fmt_out.code))

	return o

fn sorted_shape(report: JsonValue) List[String]:
	var keys = List[String]()
	shape(report, "", keys)
	return keys.sorted()

fn test_phase(ctx: Ctx, fx: Fixture, work: String, entry: String) JsonValue:
	var arguments = [
		"test",
		entry.clone(),
		"--json",
		"--build-type",
		ctx.build_type.clone(),
	]

	if not fx.args.is_empty():
		arguments.append("--")
		arguments = arguments.concat(fx.args)

	out := ctx.invoke(fx, arguments, work, fx.stdin)

	// The structured `fault` beside a failure's text was never in the recorded oracle.
	report := without_key(parse_json_output(out, work), "fault")
	keys := sorted_shape(report)
	var o = process_fields(object(), out)
	o = with(o, "report", without_key(report, "duration_ns"))
	o = with(o, "shape", strings_of(keys))
	return set_stderr(ctx, fx, out, o, work)

// Observes `fx` using `ctx.ms` in a work directory named `slot` under the scratch root.
export fn observe(ctx: Ctx, fx: Fixture, slot: String) JsonValue:
	work := f"{ctx.scratch}/{slot}"
	void remove(work, recursive: true)

	materialized := materialize(fx, work)
	var result = object()

	if materialized.is_error():
		result = with(result, "harness_error", text(materialized.err().message))
	else:
		entry := materialized.get()

		if fx.phase == Phase.Parse:
			result = parse_phase(ctx, fx, work, entry)
		else if fx.phase == Phase.Check:
			result = check_phase(ctx, fx, work, entry)
		else if fx.phase == Phase.Run:
			result = run_phase(ctx, fx, work, entry)
		else:
			result = test_phase(ctx, fx, work, entry)

	void remove(work, recursive: true)
	return result

// True when a file under `dir` names a `../` path, which can reach outside the fixture.
fn mentions_parent_path(dir: String) Bool:
	for entry in list(dir).get_or([]):
		path := f"{dir}/{entry.name}"

		if entry.directory:
			if mentions_parent_path(path): return true
		else if data := read_file(path).wait():
			if content := data.decode_utf8():
				if content.contains("../"): return true

	return false

// `content` without the batch directory prefix `dir` of a relative path, so a path reads as it
// does when the fixture is checked from its own directory.
fn strip_dir(content: String, dir: String) String:
	var out = ""
	var rest = content.clone()

	while true:
		found := rest.index_of(dir)
		if found.is_none(): break

		at := found.get()
		out += rest.slice(0, at)

		var starts_path = true

		if not out.is_empty():
			last := out.as_bytes().get(out.length() - 1)
			starts_path = not (is_name_byte(last) or last == 46 or last >= 128)

		if not starts_path: out += dir
		rest = rest.slice(at + dir.length(), rest.length())

	return out + rest

// The check observation of fixture `i` of a batch run in `root`, or none when the run
// wrote no document with the terminal output for it.
fn batch_check_result(result: JsonValue, root: String, i: Int) JsonValue?:
	work := f"{root}/w{i}"
	var code: Int? = none
	if member := result.get("exit_code"): code = member.as_int()
	if code.is_none(): return none

	var document: JsonValue? = none
	if member := result.get("document"): document = member.clone()
	if document.is_none(): return none
	if document.get().get("text").is_none(): return none

	slash := f"w{i}/"
	backslash := f"w{i}\\"
	report := normalized(
		map_strings(
			document.get(),
			fn s: strip_dir(strip_dir(s, slash), backslash)
		),
		work,
	)
	terminal := report.get("text")
	if terminal.is_none(): return none

	observation := check_observation(
		report.clone(),
		Output(code: code.get()),
		code.get(),
		text_field(terminal.get(), "stdout"),
		text_field(terminal.get(), "stderr"),
	)
	return observation

// Observes several check fixtures with one `ms check --each`, which loads the standard
// library once. A fixture the batch could not report is observed on its own, so a crash
// or timeout in one fixture still names that fixture. `slot` names the batch's
// directory under the scratch root.
export fn observe_check_batch(
	ctx: Ctx,
	fixtures: List[Fixture],
	slot: String,
) List[JsonValue]:
	root := f"{ctx.scratch}/{slot}"
	void remove(root, recursive: true)

	var targets = List[String]()
	var positions = List[Int]()

	for at in 0..fixtures.length():
		work := f"{root}/w{at}"
		materialized := materialize(fixtures[at], work)

		// A path that leaves the fixture directory prints differently from a batch
		// root.
		if materialized.is_ok() and not mentions_parent_path(work):
			positions.append(targets.length())
			targets.append(f"w{at}/{materialized.get()}")
		else:
			positions.append(-1)

	var arguments = ["check"].concat(
		targets
	).concat(["--json", "--with-text", "--each"])
	var timeout = deadline(0.0)
	for fx in fixtures:
		timeout = timeout.add(ctx.timeout(fx))

	out := ctx.invoke_within(timeout, arguments, root, "".to_bytes())
	var results = List[JsonValue]()

	if document := parse_text(out.stdout):
		if found := document.get("results"):
			batch := found.as_list().get_or([])
			if batch.length() == targets.length(): results = batch

	var observed = List[JsonValue]()

	for at in 0..fixtures.length():
		var from_batch: JsonValue? = none
		if not results.is_empty() and positions[at] >= 0:
			from_batch = batch_check_result(results[positions[at]], root, at)

		if value := from_batch:
			observed.append(value)
		else:
			observed.append(observe(ctx, fixtures[at], f"{slot}-{at}"))

	void remove(root, recursive: true)
	return observed

fn test_name_prefix(fx: Fixture, at: Int) String:
	return f"w{at}/{fx.entry}::"

// The names of the tests of `report` that start with `prefix` (separators read as `/`),
// and how many of them passed.
type Members:
	names: List[String] = []
	total: Int = 0

fn members_of(tests: List[JsonValue], prefix: String) Members:
	var members = Members()

	for item in tests:
		name := string_member(item, "name").replace("\\", "/")
		rest := name.cut_prefix(prefix)
		if rest.is_none(): continue

		members.total += 1

		status := string_member(item, "status")
		if status == "passed": members.names.append(rest.get())

	return members

// The observation of a fixture whose tests all passed, rebuilt from the batch's report.
fn passed_observation(fx: Fixture, names: List[String], shape_keys: JsonValue) JsonValue:
	var stdout = ""
	var listed = List[JsonValue]()

	for at in 0..names.length():
		name := f"{fx.entry}::{names[at]}"
		stdout += f"RUN {name}\nPASS {name}\n"

		var entry = with(object(), "index", number(at))
		entry = with(entry, "name", text(name))
		listed.append(with(entry, "status", text("passed")))

	count := names.length()
	stdout += f"{count} tests, 0 failed\n"

	var summary = with(object(), "available", number(count))
	summary = with(summary, "selected", number(count))
	summary = with(summary, "passed", number(count))
	summary = with(summary, "failed", number(0))
	summary = with(summary, "skipped", number(0))
	summary = with(summary, "not_run", number(0))

	var report = with(object(), "repeat", number(1))
	report = with(report, "format", number(1))
	report = with(report, "source_root", text("<DIR>"))
	report = with(report, "tests", list_of(listed))
	report = with(report, "summary", summary)
	report = with(report, "completed", flag(true))
	report = with(report, "exit_code", number(0))
	report = with(report, "stdout", text(stdout))
	report = with(report, "diagnostics", list_of([]))

	var o = with(object(), "exit_code", number(0))
	o = with(o, "report", report)
	o = with(o, "shape", shape_keys.clone())
	return with(o, "stderr", text(""))

fn none_for_all(count: Int) List[JsonValue?]:
	var out = List[JsonValue?]()
	for slot in 0..count:
		out.append(none)
	return out

// Observations of single-file test fixtures that passed cleanly, rebuilt from one
// `ms test` run of all of them: the compiler builds the test runner and the shared
// modules once. An entry is none when the batch did not run cleanly or its tests do not
// account for that fixture, and the caller observes that fixture alone.
export fn observe_test_batch(
	ctx: Ctx,
	fixtures: List[Fixture],
	slot: String,
) List[JsonValue?]:
	root := f"{ctx.scratch}/{slot}"
	void remove(root, recursive: true)

	var targets = List[String]()

	for at in 0..fixtures.length():
		materialized := materialize(fixtures[at], f"{root}/w{at}")
		if materialized.is_error(): return none_for_all(fixtures.length())

		targets.append(f"w{at}/{materialized.get()}")

	var arguments = ["test"].concat(
		targets
	).concat(["--json", "--build-type", ctx.build_type.clone()])

	// A member that hangs fails its own run; the batch does not wait for every timeout.
	var timeout = deadline(0.0)
	for fx in fixtures:
		timeout = timeout.add(ctx.timeout(fx))

	cap := deadline(300.0 * ctx.timeout_scale)
	limit := if timeout.compare(cap) < 0: timeout.clone() else: cap.clone()
	out := ctx.invoke_within(limit, arguments, root, "".to_bytes())
	void remove(root, recursive: true)
	if (
		out.code != 0
		or out.timed_out
		or not out.spawn_error.is_empty()
		or not out.stderr.is_empty()
	):
		return none_for_all(fixtures.length())

	report := without_key(parse_json_output(out, root), "fault")
	completed := bool_member(report, "completed")
	var tests = List[JsonValue]()

	if found := report.get("tests"):
		tests = found.as_list().get_or([])
	else:
		return none_for_all(fixtures.length())

	if not completed: return none_for_all(fixtures.length())

	shape_keys := strings_of(sorted_shape(report))
	var observed = List[JsonValue?]()

	for at in 0..fixtures.length():
		members := members_of(tests, test_name_prefix(fixtures[at], at))

		// A test that did not pass leaves the fixture to a run of its own.
		if members.names.is_empty() or members.names.length() != members.total:
			observed.append(none)
		else:
			observed.append(passed_observation(fixtures[at], members.names, shape_keys))

	return observed
