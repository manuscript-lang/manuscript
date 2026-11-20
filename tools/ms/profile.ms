// `ms profile <file.ms|ms.toml> [--out-dir directory] [--top n] [--allocs] [--json]
//            [--build-type level] [-- program arguments]`
//
// Builds the program, runs it with the runtime's sampling profiler switched on
// (`MS_PROFILE` names the folded-stack file the runtime writes), and turns what it
// wrote into a bundle: `program`, `profile.folded`, `profile.pb`, `top.txt`,
// `manifest.json`. The build is the Rust `ms build` until libms can link a whole
// program. The command returns the program's exit status; SIGINT and SIGTERM go on to
// the program (`forward.ms`).
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	promise from "@std/concurrency/promise.ms",
	base64_encode from "@std/data/encoding.ms",
	JsonValue from "@std/data/json.ms",
	ReadStream, stderr, stdout from "@std/io/io.ms",
	working_directory from "@std/os/env.ms",
	create_directory, read_file, remove, write_file from "@std/os/fs.ms",
	join, resolve from "@std/os/path.ms",
	RunOptions, SpawnOptions, Stdio, run, spawn from "@std/os/process.ms",
	now from "@std/time.ms",

	Invocation from "./args.ms",
	rust_cli from "./bridge.ms",
	errno_text from "./errno.ms",
	forward_signals, hold from "./forward.ms",
	flag, list_of, number, object, render_document, text, with from "./json_out.ms",
	Allocs,
	Folded,
	encode_pprof,
	parse_folded,
	percent_text,
	read_allocs,
	render_allocs,
	render_top from "./profile_data.ms",
)

DEFAULT_OUT_DIR := "profile"
DEFAULT_TOP := 20
PERF_REPORT := "perf report -i perf.data --no-children"

type Artifact:
	kind: String
	path: String
	state: String

// A failure the document and the terminal both report.
type Problem:
	phase: String
	message: String

fn say(message: String) Void:
	stdout().write(message).get()

fn complain(message: String) Void:
	stderr().write(message + "\n").get()

fn perf_record(program: String, arguments: List[String]) String:
	var command = f"perf record -F 999 --call-graph fp -o perf.data -- {program}"
	for argument in arguments: command += f" {argument}"
	return command

fn perf_help(program: String, arguments: List[String]) String:
	return f"To sample with perf instead (no ms involved):\n  {perf_record(program, arguments)}\n  {PERF_REPORT}\nBuilds keep frame pointers, DWARF line tables and a perf map (/tmp/perf-<pid>.map), so perf resolves Manuscript function names and lines.\n"

// The build level in its canonical spelling; empty means Release.
fn build_type_of(name: String) String:
	lowered := name.lower()
	if lowered == "debug": return "Debug"
	if lowered == "minsizerel": return "MinSizeRel"

	return "Release"

fn position(file: String) JsonValue:
	var at = object()
	at = with(at, "file", text(file))
	at = with(at, "line", number(1))
	at = with(at, "column", number(1))
	return with(at, "offset", number(0))

fn problem_json(problem: Problem, file: String) JsonValue:
	var out = object()
	out = with(out, "code", text("MSN001"))
	out = with(out, "phase", text(problem.phase))
	out = with(out, "message", text(problem.message))
	return with(out, "position", position(file))

fn artifacts_json(artifacts: List[Artifact]) JsonValue:
	var items = List[JsonValue]()

	for artifact in artifacts:
		var item = object()
		item = with(item, "kind", text(artifact.kind))
		item = with(item, "path", text(artifact.path))
		items.append(with(item, "state", text(artifact.state)))

	return list_of(items)

// The document every native command prints with `--json`.
fn native_document(
	inv: Invocation,
	build_type: String,
	output: String,
	completed: Bool,
	status: Int,
	reason: String,
	artifacts: List[Artifact],
	program_output: Bytes,
	problems: List[Problem],
) JsonValue:
	var document = object()
	document = with(document, "format", number(1))
	document = with(document, "command", text(inv.command))
	document = with(document, "build_type", text(build_type))
	document = with(document, "source_root", text(""))
	document = with(document, "output", text(output))
	document = with(document, "completed", flag(completed))
	document = with(document, "exit_code", number(status))
	if not reason.is_empty(): document = with(document, "reason", text(reason))
	document = with(document, "artifacts", artifacts_json(artifacts))

	if printed := program_output.decode_utf8():
		document = with(document, "stdout", text(printed))
	else:
		document = with(document, "stdout", text(""))
		document = with(document, "stdout_base64", text(base64_encode(program_output)))

	var found = List[JsonValue]()
	for problem in problems: found.append(problem_json(problem, inv.filename))
	return with(document, "diagnostics", list_of(found))

// A command that stopped before it had a profile.
fn fail(
	inv: Invocation,
	build_type: String,
	output: String,
	problem: Problem,
	status: Int,
	program_output: Bytes,
) Int:
	if not problem.message.is_empty() and problem.phase != "build": complain(
		problem.message
	)
	if not inv.structured: return status

	document := native_document(
		inv,
		build_type,
		output,
		false,
		status,
		f"{problem.phase}_error",
		[],
		program_output,
		[problem],
	)
	say(render_document(document))
	return status

fn text_of(data: Bytes) String:
	return data.decode_utf8().get_or("")

// Reads every chunk of the program's standard output.
fn drain(var stream: ReadStream[Bytes]) Bytes!:
	var all = BytesBuilder()

	while true:
		if chunk := stream.next()?:
			all.append_bytes(chunk)
		else:
			break

	return ok(all.build())

fn rate_number(part: Int, total: Int) JsonValue:
	return JsonValue.NumberValue(percent_text(part, total))

fn profile_json(
	profile: Folded,
	top: Int,
	program: String,
	arguments: List[String],
) JsonValue:
	total := profile.total()
	entries := profile.top()
	var rows = List[JsonValue]()

	for at in 0..entries.length():
		if at >= top: break

		entry := entries[at].clone()
		var row = object()
		row = with(row, "function", text(entry.function))
		row = with(row, "flat", number(entry.flat))
		row = with(row, "flat_percent", rate_number(entry.flat, total))
		row = with(row, "cum", number(entry.cum))
		row = with(row, "cum_percent", rate_number(entry.cum, total))
		rows.append(row)

	var perf = object()
	perf = with(perf, "record", text(perf_record(program, arguments)))
	perf = with(perf, "report", text(PERF_REPORT))

	var out = object()
	out = with(out, "samples", number(total))
	out = with(out, "hz", number(profile.hz))
	out = with(out, "duration_ns", number(total * (1000000000 / profile.hz)))
	out = with(out, "top", list_of(rows))
	return with(out, "perf", perf)

fn allocs_json(profile: Allocs) JsonValue:
	var rows = List[JsonValue]()

	for at in 0..profile.rows.length():
		if at >= profile.top: break

		row := profile.rows[at].clone()
		var item = object()
		item = with(item, "function", text(row.function))
		item = with(item, "allocations", number(row.allocations))
		rows.append(with(item, "bytes", number(row.bytes)))

	var out = object()
	out = with(out, "period", number(profile.period))
	out = with(out, "allocations", number(profile.allocations))
	out = with(out, "bytes", number(profile.bytes))
	return with(out, "top", list_of(rows))

fn read_text(path: String) String?:
	if data := read_file(path).wait(): return data.decode_utf8()
	return none

// Builds `inv.filename` into `program` with the Rust `ms`; stderr is passed on, and the
// status and text of it are returned.
fn build_program(inv: Invocation, program: String, build_type: String) CommandResult:
	var arguments = [
		"build",
		inv.filename.clone(),
		"-o",
		program.clone(),
		"--build-type",
		build_type.clone(),
	]
	var env = Map[String, String]()
	if inv.allocs: env.add("MS_BUILD_PROFILE_ALLOCS", "1")

	built := run(rust_cli(), arguments, RunOptions(env: env)).wait()
	if built.is_error():
		return CommandResult(status: 1, errors: f"ms: cannot run {rust_cli()}")

	return CommandResult(
		status: built.get().exit_code,
		errors: text_of(built.get().stderr),
	)

type CommandResult:
	status: Int
	errors: String

export fn run_profile(inv: Invocation) Int:
	display_output := if inv.output.is_empty(): DEFAULT_OUT_DIR else: inv.output.clone()
	top := if inv.top == 0: DEFAULT_TOP else: inv.top
	build_type := build_type_of(inv.build_type_name)
	structured := inv.structured
	nothing := "".to_bytes()
	here := working_directory()
	if here.is_error():
		return fail(
			inv,
			build_type,
			display_output,
			Problem(phase: "build", message: here.err().message),
			1,
			nothing,
		)

	resolved := resolve(here.get(), [display_output.clone()])
	if resolved.is_error():
		return fail(
			inv,
			build_type,
			display_output,
			Problem(phase: "build", message: resolved.err().message),
			1,
			nothing,
		)

	output := resolved.get()
	program := join([output.clone(), "program"])
	folded_path := join([output.clone(), "profile.folded"])
	allocs_path := join([output.clone(), "allocs.folded"])
	made := create_directory(output.clone())

	if made.is_error():
		message := f"profile directory must be new: mkdir {output}: {errno_text(made.err())}; choose a path that does not exist with --out-dir <directory>"
		return fail(
			inv,
			build_type,
			output,
			Problem(phase: "artifact", message: message),
			1,
			nothing,
		)

	built := build_program(inv, program, build_type)
	if not built.errors.is_empty(): stderr().write(built.errors.clone()).get()

	if built.status != 0:
		// This invocation created the directory; a failed build must not block a retry.
		void remove(output.clone(), true)
		return fail(
			inv,
			build_type,
			output,
			Problem(phase: "build", message: built.errors.trim()),
			built.status,
			nothing,
		)

	var env = Map[String, String]()
	env.add("MS_PROFILE", folded_path.clone())
	if inv.allocs: env.add("MS_PROFILE_ALLOCS", allocs_path.clone())

	spawned := spawn(
		program.clone(),
		inv.arguments.clone(),
		SpawnOptions(
			stdin: Stdio.Inherit,
			stdout: if structured: Stdio.Pipe else: Stdio.Inherit,
			stderr: Stdio.Inherit,
			env: env,
		),
	)
	if spawned.is_error():
		return fail(
			inv,
			build_type,
			output,
			Problem(phase: "execution", message: spawned.err().message),
			1,
			nothing,
		)

	child := spawned.get()
	_hold := hold()
	_relay := forward_signals(child.pid())
	var captured = nothing.clone()
	var waited: Int! = ok(0)

	if structured:
		var pipe = child.stdout()
		reader := promise(fn: drain(pipe))
		waited = child.wait()
		captured = reader.wait().get_or(nothing.clone())
	else:
		waited = child.wait()

	if waited.is_error():
		return fail(
			inv,
			build_type,
			output,
			Problem(phase: "execution", message: waited.err().message),
			1,
			captured,
		)

	code := waited.get()
	program_status := if code < 0: 255 else: code
	reason := if code < 0: "interrupted" else: "program_exit"
	var problems = List[Problem]()
	var artifacts = [
		Artifact(kind: "executable", path: program.clone(), state: "verified")
	]
	var profile_part = JsonValue.Null
	var report = ""
	var final_status = program_status
	read := read_text(folded_path)

	if read.is_none():
		message := f"the program wrote no profile to {folded_path} (it exited with status {program_status}); a runtime built without profiling support or a program killed before cleanup writes nothing"
		problems.append(Problem(phase: "artifact", message: message.clone()))
		artifacts.append(
			Artifact(
				kind: "folded",
				path: folded_path.clone(),
				state: "missing",
			)
		)
		if not structured: complain(message)
		if final_status == 0: final_status = 1
	else:
		parsed := parse_folded(read.get())

		if parsed.is_error():
			message := f"cannot read {folded_path}: {parsed.err().message}"
			problems.append(Problem(phase: "artifact", message: message.clone()))
			artifacts.append(
				Artifact(
					kind: "folded",
					path: folded_path.clone(),
					state: "written",
				)
			)
			if not structured: complain(message)
			if final_status == 0: final_status = 1
		else:
			profile := parsed.get()
			pprof_path := join([output.clone(), "profile.pb"])
			top_path := join([output.clone(), "top.txt"])
			manifest_path := join([output.clone(), "manifest.json"])
			report = render_top(profile, top)

			total := profile.total()
			var manifest = object()
			manifest = with(manifest, "format", number(1))
			manifest = with(manifest, "executable", text("program"))
			manifest = with(manifest, "folded", text("profile.folded"))
			manifest = with(manifest, "pprof", text("profile.pb"))
			manifest = with(manifest, "top", text("top.txt"))
			manifest = with(manifest, "samples", number(total))
			manifest = with(manifest, "hz", number(profile.hz))

			stamp := now()
			written := write_bundle(
				pprof_path,
				encode_pprof(
					profile,
					stamp.seconds * 1000000000 + stamp.nanos,
				),
				top_path,
				report,
				manifest_path,
				render_document(manifest),
			)

			if written.is_error():
				message := f"cannot write the profile bundle in {output}: {written.err().message}"
				problems.append(Problem(phase: "artifact", message: message.clone()))
				if final_status < 1: final_status = 1

			artifacts.append(
				Artifact(
					kind: "folded",
					path: folded_path.clone(),
					state: "written",
				)
			)
			artifacts.append(
				Artifact(
					kind: "pprof",
					path: pprof_path.clone(),
					state: "written",
				)
			)
			artifacts.append(
				Artifact(
					kind: "top",
					path: top_path.clone(),
					state: "written",
				)
			)
			artifacts.append(
				Artifact(
					kind: "manifest",
					path: manifest_path.clone(),
					state: "written",
				)
			)
			profile_part = profile_json(profile, top, program, inv.arguments)

	var allocs_text = ""
	var allocs_part = JsonValue.Null

	if inv.allocs:
		counts := read_text(allocs_path)
		bytes := read_text(f"{allocs_path}.bytes")

		if counts.is_none() or bytes.is_none():
			missing := if counts.is_none(): allocs_path.clone() else: f"{allocs_path}.bytes"
			message := f"the program wrote no allocation profile to {missing}; a program that never allocates on its main thread, a runtime built without profiling support or a program killed before cleanup writes nothing"
			problems.append(Problem(phase: "artifact", message: message.clone()))
			if not structured: complain(message)
			if final_status < 1: final_status = 1
		else:
			allocs := read_allocs(allocs_path, counts.get(), bytes.get(), top)

			if allocs.is_error():
				message := allocs.err().message
				problems.append(Problem(phase: "artifact", message: message.clone()))
				if not structured: complain(message)
				if final_status < 1: final_status = 1
			else:
				allocs_text = render_allocs(allocs.get())

				text_path := join([output.clone(), "allocs.txt"])
				wrote := write_file(
					text_path.clone(),
					allocs_text.clone(),
					replace: true,
				).wait()

				if wrote.is_error():
					complain(f"cannot write {text_path}: {wrote.err().message}")
					if final_status < 1: final_status = 1

				artifacts.append(
					Artifact(
						kind: "allocs",
						path: allocs_path.clone(),
						state: "written",
					)
				)
				artifacts.append(
					Artifact(
						kind: "allocs_bytes",
						path: f"{allocs_path}.bytes",
						state: "written",
					)
				)
				artifacts.append(
					Artifact(
						kind: "allocs_top",
						path: text_path.clone(),
						state: "written",
					)
				)
				allocs_part = allocs_json(allocs.get())

	if structured:
		var document = native_document(
			inv,
			build_type,
			output,
			true,
			final_status,
			reason,
			artifacts,
			captured,
			problems,
		)

		if allocs_part != JsonValue.Null:
			base := if profile_part == JsonValue.Null: object() else: profile_part.clone()
			profile_part = with(base, "allocs", allocs_part)

		if profile_part != JsonValue.Null: document = with(
			document,
			"profile",
			profile_part,
		)
		say(render_document(document))
		return final_status

	if not report.is_empty():
		say(report)
		if not allocs_text.is_empty(): say(f"\n{allocs_text}")
		say(f"\nProfile bundle: {display_output}\n")
		for entry in [
			[
				"profile.folded", "folded stacks (flamegraph.pl, inferno, speedscope)"
			],
			[
				"profile.pb", "pprof protobuf (go tool pprof, pprof -http=:8080)"
			],
			["top.txt", "this report"],
			["program", "the profiled executable"],
		]:
			say(
				f"  {join([display_output.clone(), entry[0].clone()]).pad_end(28, " ")} {entry[1]}\n"
			)
		say("\n")
		say(perf_help(join([display_output.clone(), "program"]), inv.arguments))

	return final_status

// Writes the three generated files of the bundle, stopping at the first failure.
fn write_bundle(
	pprof_path: String,
	pprof: Bytes,
	top_path: String,
	report: String,
	manifest_path: String,
	manifest: String,
) Void!:
	write_file(pprof_path, pprof, replace: true).wait()?
	write_file(top_path, report, replace: true).wait()?
	write_file(manifest_path, manifest, replace: true).wait()?
