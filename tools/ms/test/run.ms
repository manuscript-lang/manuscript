// `ms test [target] [options] [-- program arguments]`: builds the tests of a program or
// project into one executable, runs them together under the harness and prints one
// `RUN`/`PASS`/`FAIL` block per test and a summary, or the `--json` document.
// Exit statuses: 0 every selected test passed; 1 a test failed, none matched, or the
// build failed; 2 usage error.
//
// The compiler stage is the Rust `ms build` with `MS_BUILD_TARGET=tests`, which also
// writes `<output>.tests`: the source root, the project root and each test's identity.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	base64_encode from "@std/data/encoding.ms",
	JsonValue, parse from "@std/data/json.ms",
	stderr, stdout, stdout_bytes from "@std/io/io.ms",
	working_directory from "@std/os/env.ms",
	read_file, temporary from "@std/os/fs.ms",
	dirname, join, resolve from "@std/os/path.ms",
	RunOptions, process_info, run from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",
	Duration, monotonic, nanoseconds, seconds from "@std/time.ms",

	Invocation from "../args.ms",
	rust_cli from "../bridge.ms",
	errno_text from "../errno.ms",
	flag, list_of, number, object, render_document, text, with from "../json_out.ms",
	Measured, baseline_regressions, describe_stats, run_one from "./bench.ms",
	Fault, decode, fault_json, from_text, is_fault_status from "./fault.ms",
	debug_duration from "./format.ms",
	TestOptions from "./options.ms",
	file_numbers, select, shuffled from "./plan.ms",
	Outcome, Together, run_together from "./supervise.ms",
)

// The command's own output: the terminal, or the `--json` document's `stdout` member.
type Out:
	captured: Bool
	buffer: BytesBuilder = BytesBuilder()

fn var Out.write(data: Bytes) Void:
	if self.captured:
		self.buffer.append_bytes(data)
	else:
		stdout_bytes().write(data).get()

fn var Out.line(message: String) Void:
	self.write((message + "\n").to_bytes())

fn complain(message: String) Void:
	stderr().write(message + "\n").get()

// One selected test and what happened to it.
type Case:
	name: String
	// not_run, passed, failed or skipped.
	status: String = "not_run"
	failure: String = ""
	// The `file:line:column` site of a failed expectation.
	site: String = ""
	fault: Fault? = none
	stats: JsonValue? = none
	nanos: Int = 0

type Document:
	// A bench run: the cases are listed under `benches`.
	bench: Bool = false
	listed: Bool = false
	repeat: Int = 0
	shuffle_seed: Int? = none
	source_root: String = ""
	cases: List[Case] = []
	available: Int = 0
	completed: Bool = false
	exit_code: Int = 1
	reason: String = ""
	nanos: Int = 0
	stdout: Bytes = "".to_bytes()
	diagnostics: List[JsonValue] = []

fn count(document: Document, status: String) Int:
	var found = 0
	for each in document.cases:
		if each.status == status: found += 1
	return found

// A site's position as the document spells it, split from the right because file names
// may hold colons.
fn position_json(site: String) JsonValue?:
	first := site.rsplit_once(":")
	if first.is_none(): return none

	second := first.get().before.rsplit_once(":")
	if second.is_none(): return none

	line := second.get().after.parse_int()
	column := first.get().after.parse_int()
	if line.is_none() or column.is_none(): return none

	var out = object()
	out = with(out, "file", text(second.get().before))
	out = with(out, "line", number(line.get()))
	out = with(out, "column", number(column.get()))
	out = with(out, "offset", number(0))
	return out

fn document_json(document: Document) JsonValue:
	var out = object()
	if document.listed: out = with(out, "listed", flag(true))
	if document.repeat > 0: out = with(out, "repeat", number(document.repeat))
	if seed := document.shuffle_seed: out = with(out, "shuffle_seed", number(seed))

	var items = List[JsonValue]()

	for at in 0..document.cases.length():
		each := document.cases[at]
		var item = object()
		item = with(item, "index", number(at))
		item = with(item, "duration_ns", number(each.nanos))
		item = with(item, "name", text(each.name))
		item = with(item, "status", text(each.status))

		if not each.failure.is_empty():
			item = with(item, "failure", text(each.failure))
			if position := position_json(each.site): item = with(
				item,
				"position",
				position,
			)

		if fault := each.fault: item = with(item, "fault", fault_json(fault))
		if stats := each.stats: item = with(item, "stats", stats.clone())
		items.append(item)

	finished := (
		count(document, "passed")
		+ count(document, "failed")
		+ count(document, "skipped")
	)
	not_run := if document.completed: document.cases.length() - finished else: 0
	var summary = object()
	summary = with(summary, "available", number(document.available))
	summary = with(summary, "selected", number(document.cases.length()))
	summary = with(summary, "passed", number(count(document, "passed")))
	summary = with(summary, "failed", number(count(document, "failed")))
	summary = with(summary, "skipped", number(count(document, "skipped")))
	summary = with(summary, "not_run", number(not_run))
	summary = with(summary, "duration_ns", number(document.nanos))
	out = with(out, "format", number(1))
	out = with(out, "source_root", text(document.source_root))
	out = with(out, if document.bench: "benches" else: "tests", list_of(items))
	out = with(out, "summary", summary)
	out = with(out, "completed", flag(document.completed))
	out = with(out, "exit_code", number(document.exit_code))
	if not document.reason.is_empty(): out = with(out, "reason", text(document.reason))

	shown := document.stdout.decode_utf8()

	if shown.is_some():
		out = with(out, "stdout", text(shown.get()))
	else:
		out = with(out, "stdout", text(""))
		out = with(out, "stdout_base64", text(base64_encode(document.stdout)))

	return with(out, "diagnostics", list_of(document.diagnostics.clone()))

// How a test's outcome reads in the `RUN`/`FAIL` block.
fn failed_outcome(message: String) Outcome:
	return Outcome(kind: "failed", message: message)

// Where the tests of every file ran, in completion order per test, retrying the files a
// crash or a timeout did not cover in a new process.
fn run_all(
	executable: String,
	working: String,
	options: TestOptions,
	indices: List[Int],
	files: List[Int],
	var out: Out,
) Map[Int, List[Outcome]]:
	var all = Map[Int, List[Outcome]]()
	var remaining = indices.clone()

	while not remaining.is_empty():
		together := run_together(executable, working.clone(), options, remaining)
		out.write(together.printed.clone())

		for index in together.results.keys():
			var queue = all.get_or(index, [])
			queue.extend(together.results.get_or(index, []))
			all.add(index, queue)

		crashed := together.timed_out.is_empty()

		// Each ended file's failure, and why its later tests did not run.
		var why = Map[Int, String]()
		var later = Map[Int, String]()

		for file in together.faults.keys():
			why.add(file, together.faults.get_or(file, ""))
			later.add(file, "an earlier test in this file faulted")

		for index in remaining:
			file := files.get_or(index, -1)
			if all.contains(index) or why.contains(file): continue

			if together.timed_out.contains(index):
				limit := debug_duration(
					options.timeout.get_or(
						nanoseconds(0)
					).to_nanoseconds()
				)
				why.add(
					file,
					f"timed out after {limit}; a test that never waits is stopped with its process",
				)
				later.add(file, "an earlier test in this file timed out")
			else if crashed and together.running.contains(index):
				why.add(file, f"the test process {together.ended} while this test ran")
				later.add(
					file,
					f"the test process {together.ended} while an earlier test in this file ran",
				)

		var next = List[Int]()

		for index in remaining:
			if all.contains(index): continue

			file := files.get_or(index, -1)

			if not why.contains(file):
				next.append(index)
				continue

			reason := why.get_or(file, "")
			var outcome = failed_outcome(reason.clone())

			if not together.started.contains(index):
				outcome = Outcome(kind: "not_run", message: later.get_or(file, ""))
			else if together.faults.contains(file):
				outcome = faulted(reason, together, file)

			var queue = all.get_or(index, [])
			queue.append(outcome)
			all.add(index, queue)

		if next.length() == remaining.length():
			// Nothing finished: the process cannot run tests at all.
			for index in next:
				var queue = all.get_or(index, [])
				queue.append(
					failed_outcome(
						f"the test process {together.ended} before this test started"
					)
				)
				all.add(index, queue)

			break

		remaining = next

	return all

// The outcome of the test that was running when `file` faulted.
fn faulted(reason: String, together: Together, file: Int) Outcome:
	var fault = from_text(reason)

	if record := together.fault_records.get(file):
		if decoded := decode(record):
			// The harness's own frames sit below the test's.
			var cut = decoded.trace.length()
			for at in 0..decoded.trace.length():
				if (
					cut == decoded.trace.length()
					and decoded.trace[at].file.ends_with(
						"internal/test_runner.ms"
					)
				):
					cut = at
			fault = Fault(
				decoded.kind,
				decoded.exit_code,
				decoded.message,
				decoded.trace.slice(0, cut).get_or([]),
				decoded.truncated,
				decoded.cleanup_faults,
			)

	var outcome = Outcome(
		kind: "faulted",
		message: reason,
		printed: together.fault_outputs.get_or(file, "".to_bytes()),
	)
	if fault.is_none(): outcome.kind = "failed"
	outcome.fault = fault
	return outcome

fn build_failed(
	message: String,
	var document: Document,
	structured: Bool,
	var out: Out,
) Int:
	complain(message)
	if not structured: return 1

	document.diagnostics.append(early_diagnostic(message))
	return finish_document(document, 1, out)

fn early_diagnostic(message: String) JsonValue:
	var position = object()
	position = with(position, "file", text(""))
	position = with(position, "line", number(0))
	position = with(position, "column", number(0))
	position = with(position, "offset", number(0))

	var out = object()
	out = with(out, "code", text("MST001"))
	out = with(out, "phase", text("execution"))
	out = with(out, "message", text(message))
	out = with(out, "position", position)
	return out

fn finish_document(var document: Document, status: Int, var out: Out) Int:
	document.exit_code = status
	document.stdout = out.buffer.drain()
	stdout().write(render_document(document_json(document))).get()
	return status

// Builds the tests (or benches) into `executable`; the listing is `<executable>.tests`.
fn build_tests(
	inv: Invocation,
	executable: String,
	structured: Bool,
	var document: Document,
	var out: Out,
) Int?:
	var args = ["build", inv.filename.clone(), "-o", executable.clone()]

	if not inv.build_type_name.is_empty():
		args.append("--build-type")
		args.append(inv.build_type_name.clone())

	for link in inv.link:
		args.append("--link")
		args.append(link.clone())

	if structured: args.append("--json")

	var env = Map[String, String]()
	if inv.command == "test" and inv.targets.length() > 1:
		env.add("MS_BUILD_EXTRA", inv.targets.drop(1).join("\n"))
	if inv.command == "bench" and inv.tests.ops:
		env.add("MS_BUILD_COUNT_OPS", "1")
	env.add("MS_BUILD_TARGET", if inv.command == "bench": "benches" else: "tests")

	finished := run(rust_cli(), args, RunOptions(env: env)).wait()
	if finished.is_error():
		return build_failed(
			f"cannot run {rust_cli()}: {errno_text(finished.err())}",
			document,
			structured,
			out,
		)
	if finished.get().exit_code == 0: return none

	printed := finished.get().stdout.decode_utf8().get_or("")
	errors := finished.get().stderr.decode_utf8().get_or("")

	if not structured:
		stderr().write(errors).get()
		stdout().write(printed).get()
		return 1

	// The build's own document names its diagnostics.
	parsed := parse(printed)

	if parsed.is_ok():
		if listed := parsed.get().get("diagnostics"):
			document.diagnostics = listed.as_list().get_or([])
		if root := parsed.get().get("source_root"):
			document.source_root = root.as_string().get_or("")

	document.reason = "compile_error"
	return finish_document(document, 1, out)

// Lines of a file: its text split at newlines, without a trailing empty piece.
fn lines_of(data: Bytes) List[String]:
	var out = data.decode_utf8().get_or("").split("\n")
	if not out.is_empty() and out[out.length() - 1].is_empty(): out.pop()
	return out

export fn run_test(inv: Invocation) Int:
	return run_command(inv, false)

export fn run_bench(inv: Invocation) Int:
	return run_command(inv, true)

// The file name of the test program: Windows runs only files that end in `.exe`.
fn program_name() String:
	info := process_info()
	if info.is_ok() and info.get().os == "windows": return "program.exe"

	return "program"

fn run_command(inv: Invocation, bench: Bool) Int:
	var options = inv.tests.clone()
	structured := inv.structured
	var document = Document(bench: bench)

	// Calibration and every sample count against the limit.
	if bench and not options.timeout_set: options.timeout = seconds(600)

	// The counter slows the program, so run once: the count does not need more.
	if bench and options.ops:
		if options.bench_iterations.is_none(): options.bench_iterations = 1
		if options.bench_samples.is_none(): options.bench_samples = 1

	var out = Out(captured: structured)
	scratch := temporary(if bench: "manuscript-bench-" else: "manuscript-test-")
	if scratch.is_error():
		return build_failed(errno_text(scratch.err()), document, structured, out)

	holder := scratch.get()
	directory := holder.path()
	executable := join([directory, program_name()])
	failed_build := build_tests(inv, executable, structured, document, out)
	if status := failed_build: return status

	listing := read_file(f"{executable}.tests").wait()
	if listing.is_error():
		return build_failed(
			f"cannot read {executable}.tests: {errno_text(listing.err())}",
			document,
			structured,
			out,
		)

	rows := lines_of(listing.get())
	if rows.length() < 2:
		return build_failed(
			"the build listed no source root",
			document,
			structured,
			out,
		)

	document.source_root = rows[0].clone()

	available := rows.drop(2)
	cwd := working_directory()
	working := if rows[1].is_empty(): dirname(inv.filename) else: rows[1].clone()
	absolute := resolve(cwd.get_or("."), [working.clone()])
	return run_selected(
		inv,
		bench,
		options,
		executable,
		absolute.get_or(working),
		available,
		document,
		out,
	)

fn run_selected(
	inv: Invocation,
	bench: Bool,
	options: TestOptions,
	executable: String,
	working: String,
	available: List[String],
	var document: Document,
	var out: Out,
) Int:
	structured := inv.structured
	noun := if bench: "bench" else: "test"
	nouns := if bench: "benches" else: "tests"
	total := available.length()
	picked := select(available, options)

	if not picked.unknown.is_empty():
		message := f"unknown {noun} {quoted(picked.unknown)}; use --list to find full module::name identities"
		complain(message)
		if not structured: return 1

		document.reason = "no_match"
		document.diagnostics.append(early_diagnostic(message))
		return finish_document(document, 1, out)

	var selected = picked.indices.clone()

	if seed := options.shuffle:
		selected = shuffled(selected, seed)
		out.line(f"shuffle seed: {seed}")

	repeat := if options.list: 1 else: options.repeat
	var plan = List[Int]()
	for round in 0..repeat: plan.extend(selected.clone())
	document.available = total
	document.repeat = repeat
	document.shuffle_seed = options.shuffle
	for index in plan: document.cases.append(Case(name: available[index].clone()))

	filtered := (
		not options.filter.is_empty()
		or not options.matching.is_empty()
		or not options.exclude.is_empty()
		or not options.names.is_empty()
	)

	if plan.is_empty() and filtered:
		out.line(
			f"no {nouns} match selection ({total} {nouns} available); use --list to find full module::name identities"
		)
		document.completed = true
		document.reason = "no_match"
		if structured: return finish_document(document, 1, out)

		return 1

	if options.list:
		for index in plan: out.line(available[index].clone())
		document.listed = true
		document.completed = true
		document.reason = "listed"
		if structured: return finish_document(document, 0, out)

		return 0

	started := monotonic()
	var failed = 0
	var reason = ""
	var together = Map[Int, List[Outcome]]()

	if not plan.is_empty() and not bench:
		files := file_numbers(available)
		together = run_all(
			executable.clone(),
			working.clone(),
			options,
			selected,
			files,
			out,
		)

		for round in 1..repeat:
			more := run_all(
				executable.clone(),
				working.clone(),
				options,
				selected,
				files,
				out,
			)

			for index in more.keys():
				var queue = together.get_or(index, [])
				queue.extend(more.get_or(index, []))
				together.add(index, queue)

	for position in 0..plan.length():
		index := plan[position]
		name := available[index].clone()
		out.line(f"RUN {name}")

		var queue = together.get_or(index, [])
		var outcome = failed_outcome("the test reported no result")
		began := monotonic()

		if bench:
			outcome = run_one(executable.clone(), working.clone(), options, index)
			outcome.nanos = monotonic().difference(began).to_nanoseconds()
		else if not queue.is_empty():
			outcome = queue[0].clone()
			together.add(index, queue.drop(1))

		out.write(outcome.printed.clone())

		var each = document.cases[position].clone()
		each.nanos = outcome.nanos

		if outcome.kind == "passed":
			out.line(f"PASS {name}")
			each.status = "passed"
		else if outcome.kind == "measured":
			stats := outcome.stats.get()
			out.line(f"BENCH {name}: {describe_stats(stats)}")
			each.status = "passed"
			each.stats = stats.clone()
		else if outcome.kind == "not_run":
			out.line(f"NOT RUN {name}: {outcome.message}")
			each.failure = outcome.message.clone()
		else if outcome.kind == "skipped":
			out.line(f"SKIP {name}: {outcome.message}")
			each.status = "skipped"
			each.failure = outcome.message.clone()
		else:
			failed += 1
			out.line(f"FAIL {name}: {outcome.message}")
			each.status = "failed"
			each.failure = outcome.message.clone()
			each.site = outcome.site.clone()
			each.fault = outcome.fault.clone()

		document.cases[position] = each

		if failed > 0 and options.fail_fast:
			reason = "fail_fast"
			break

	if plan.is_empty() and bench:
		out.line(
			"no bench blocks found: add bench blocks to bench.ms or *_bench.ms files in the project, or pass a .ms file"
		)
		reason = "no_benches"
	else if plan.is_empty():
		out.line(
			"no test blocks found: add test blocks to test.ms or *_test.ms files in the project, or pass a .ms file"
		)
		reason = "no_tests"

	skipped := count(document, "skipped")
	not_run := count(document, "not_run")
	var summary = f"{plan.length() - not_run} {nouns}, {failed} failed"
	if skipped > 0: summary += f", {skipped} skipped"
	if not_run > 0: summary += f", {not_run} not run"
	out.line(summary)
	document.completed = true
	document.reason = reason
	document.nanos = monotonic().difference(started).to_nanoseconds()

	var status = if failed > 0: 1 else: 0

	if bench and status == 0:
		var measured = List[Measured]()
		for each in document.cases:
			if stats := each.stats: measured.append(
				Measured(each.name.clone(), stats.clone())
			)

		var lines = List[String]()
		held := baseline_regressions(options, measured, lines)
		for line in lines: out.line(line)

		if held.is_error():
			complain(held.err().message)
			status = 2
		else if held.get():
			status = 1

	if structured: return finish_document(document, status, out)

	return status

// `value` as Rust's `{:?}` prints a string.
fn quoted(value: String) String:
	return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
