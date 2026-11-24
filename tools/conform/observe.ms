// One fixture observed under an ms binary, as the JSON value its expectation records.
import (
	Bytes from "@std/bytes.ms",
	JsonValue, StringifyOptions, parse, stringify from "@std/data/json.ms",
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

	Fixture,
	Meta,
	materialize,
	parent_length,
	read_text,
	string_member,
	text_of from "./corpus.ms",
)

// What one run of ms left: its exit status and streams, as text.
export type Process:
	code Int
	stdout String
	stderr String
	timed_out Bool
	spawn_error String

export fn default_timeout(phase String) Int:
	if phase == "parse": return 30
	if phase == "check": return 60
	if phase == "run": return 120

	// A hang detector, not a speed budget: the slowest test fixtures take 15 to 20 s on
	// Linux (yaml, many-tasks) and three times that on a loaded Windows runner, so the
	// limit matches the run phase.
	return 120

export fn invoke(
	ms String,
	fx Fixture,
	args List[String],
	work String,
	input Bytes,
) Process:
	limit := if fx.timeout > 0: fx.timeout else: default_timeout(fx.phase)
	result := run(
		ms.clone(),
		args,
		RunOptions(
			cwd: work.clone(),
			timeout: seconds(limit),
			input: input.clone(),
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
	timed := (cause.kind.clone() or "") == "ETIMEDOUT"
	return Process(
		code: if timed: 137 else: 127,
		stdout: "",
		stderr: "",
		timed_out: timed,
		spawn_error: if timed: "" else: cause.message.clone(),
	)

// `text` with the work directory (as given and with forward slashes) as <DIR> and its
// parent as <SCRATCH>, the line number of a standard-library frame as <LINE>, and the
// count of a repeated frame as <COUNT>.
fn normalize_text(text String, work String) String:
	var out = text.replace(work, "<DIR>").replace(work.replace("\\", "/"), "<DIR>")
	parent_end := parent_length(work)

	if parent_end > 0:
		parent := work.slice(0, parent_end)
		out = out.replace(parent, "<SCRATCH>").replace(
			parent.replace("\\", "/"),
			"<SCRATCH>",
		)

	return mask_repeat_counts(mask_stdlib_lines(out))

// A recursive frame repeated `N more times` names its count <COUNT>: how deep a
// recursion gets before the stack ends depends on the platform's frame sizes.
fn mask_repeat_counts(text String) String:
	marker := "repeated "
	if not text.contains(marker): return text.clone()

	var out = ""
	var rest = text.clone()

	while true:
		at := rest.index_of(marker) or (-1)
		if at < 0: break

		after := rest.slice(at + marker.length(), rest.length())
		digits := leading_digits(after)
		out += rest.slice(0, at + marker.length())

		if (
			digits > 0
			and after.slice(digits, after.length()).starts_with(
				" more times"
			)
		):
			out += "<COUNT>"
			rest = after.slice(digits, after.length()).clone()
		else:
			rest = after.clone()

	return out + rest

// A standard-library frame (`@std/concurrency/promise.ms:312`) names its line as
// <LINE>, so editing a standard-library file does not change the expectation of every
// fixture that faults through it.
fn mask_stdlib_lines(text String) String:
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

fn leading_digits(text String) Int:
	var count = 0
	while count < text.length() and "0123456789".contains(text.slice(count, count + 1)): count += 1
	return count

fn path_name(name String) Bool:
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
fn normalized(value JsonValue, work String) JsonValue:
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
fn read_report(out Process, work String) JsonValue:
	parsed := parse(out.stdout)
	if document := parsed: return normalized(document, work)

	var broken = Map[String, JsonValue]()
	broken.add("unparsable_json", JsonValue.StringValue(f"{parsed.err().message}"))
	broken.add("stdout", JsonValue.StringValue(normalize_text(out.stdout, work)))
	return JsonValue.ObjectValue(broken)

export fn number(value Int) JsonValue:
	return JsonValue.NumberValue(f"{value}")

export fn text_value(value String) JsonValue:
	return JsonValue.StringValue(value.clone())

// `exit_code`, `timed_out` and `spawn_error` of a run.
fn process_fields(var fields Map[String, JsonValue], out Process) Void:
	fields.add("exit_code", number(out.code))
	if out.timed_out: fields.add("timed_out", JsonValue.BoolValue(true))
	if out.spawn_error != "": fields.add("spawn_error", text_value(out.spawn_error))

// The text of `source` below its `// conform:` header lines.
fn without_header(source String) String:
	var skip = 0

	for line in source.split("\n"):
		if not line.starts_with("// conform:"): break

		skip += line.length() + 1

	if skip > source.length(): return ""

	return source.slice(skip, source.length())

fn parse_phase(ms String, fx Fixture, work String) JsonValue:
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
	listed := report.get("diagnostics")
	if listed != null:
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

fn check_phase(ms String, fx Fixture, work String) JsonValue:
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
	text := report.get("text")

	if text != null:
		stdout = string_member(text, "stdout")
		stderr = string_member(text, "stderr")
	else:
		plain := invoke(ms, fx, ["check", fx.entry.clone()], work, "".to_bytes())
		text_code = plain.code
		stdout = normalize_text(plain.stdout, work)
		stderr = normalize_text(plain.stderr, work)

	var fields = Map[String, JsonValue]()
	process_fields(fields, json_run)

	format := report.get("format")
	if format != null: fields.add("format", format.clone())

	listed := report.get("diagnostics")

	if listed != null: fields.add("diagnostics", listed.clone())
	else: fields.add("diagnostics", JsonValue.ArrayValue([]))

	if report.get("unparsable_json") != null: fields.add("raw", report)

	var text = Map[String, JsonValue]()
	text.add("exit_code", number(text_code))
	text.add("stdout", text_value(stdout))
	text.add("stderr", text_value(stderr))
	fields.add("text", JsonValue.ObjectValue(text))
	return JsonValue.ObjectValue(fields)

fn run_phase(ms String, fx Fixture, work String, build_type String) JsonValue:
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
fn without_member(value JsonValue, name String) JsonValue:
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
fn shape(value JsonValue, path String, var out List[String]) Void:
	match value:
		ObjectValue(fields):
			for field in fields.entries():
				next := if path == "": field.key.clone() else: f"{path}.{field.key}"
				if not out.contains(next): out.append(next.clone())
				shape(field.value, next, out)
		ArrayValue(items):
			for item in items: shape(item, f"{path}[]", out)
		_: return

fn test_phase(ms String, fx Fixture, work String, build_type String) JsonValue:
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
export fn observe(ms String, fx Fixture, build_type String) JsonValue:
	scratch := temporary("ms-conform-").get()
	work := f"{scratch.path()}/w"
	create_directory(work.clone()).get()
	materialize(fx, work.clone())
	if fx.phase == "parse": return parse_phase(ms, fx, work.clone())
	if fx.phase == "check": return check_phase(ms, fx, work.clone())
	if fx.phase == "run": return run_phase(ms, fx, work.clone(), build_type)

	return test_phase(ms, fx, work.clone(), build_type)

export fn same(left JsonValue, right JsonValue) Bool:
	return stringify(left).get() == stringify(right).get()
