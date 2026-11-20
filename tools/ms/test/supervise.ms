// Runs the tests of one executable together in one process under the harness in
// `@std/internal/test_runner.ms` and collects what the harness reports. The harness appends
// records to a results file; a watcher on the results directory wakes the supervisor
// for each batch, and the supervisor stops the process when a test that never waits
// passes its limit. A fault ends the file the test ran in: the test that was running
// fails with it and the file's later tests are not run. A crash ends the files whose
// tests were running, since the culprit is not known; the other files' unfinished tests
// run again in a new process.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Promise, promise, wait_any from "@std/concurrency/promise.ms",
	JsonValue from "@std/data/json.ms",
	ReadStream from "@std/io/io.ms",
	read_file, stat, temporary, watch from "@std/os/fs.ms",
	dirname, join from "@std/os/path.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",
	Duration, Instant, milliseconds, monotonic, seconds, sleep from "@std/time.ms",

	errno_text from "../errno.ms",
	forward_signals, hold from "../forward.ms",
	Fault, decode, from_text, is_fault_status from "./fault.ms",
	TestOptions from "./options.ms",
	Kind, Parsed, Record, parse from "./records.ms",
)

// One test's result as the harness reported it, or as the supervisor decided.
export type Outcome:
	// passed, skipped, failed (a message), rejected (an expectation with a site),
	// faulted, or not_run.
	kind: String
	message: String = ""
	site: String = ""
	nanos: Int = 0
	fault: Fault? = none
	printed: Bytes = "".to_bytes()
	// The statistics a bench measured.
	stats: JsonValue? = none

// What one run of the executable reported.
export type Together:
	// Each test's outcomes, in completion order.
	results: Map[Int, List[Outcome]] = Map[Int, List[Outcome]]()
	started: Map[Int, Bool] = Map[Int, Bool]()
	// Files whose test faulted, by the harness's file number, with the fault message.
	faults: Map[Int, String] = Map[Int, String]()
	outputs: Map[Int, List[Bytes]] = Map[Int, List[Bytes]]()
	fault_records: Map[Int, Bytes] = Map[Int, Bytes]()
	fault_outputs: Map[Int, Bytes] = Map[Int, Bytes]()
	// Tests started and not yet reported, with the file and when they were seen start.
	running_file: Map[Int, Int] = Map[Int, Int]()
	running_since: Map[Int, Instant] = Map[Int, Instant]()
	// Tests stopped with the process for running past `--timeout`.
	timed_out: List[Int] = []
	// Tests that had started and not reported when the process ended.
	running: List[Int] = []
	// How the process ended.
	ended: String = ""
	// What the process printed on standard output.
	printed: Bytes = "".to_bytes()

// What woke the supervisor.
type Event:
	kind: String
	bytes: Bytes = "".to_bytes()
	size: Int = 0

fn position_of(site: String) Int:
	return 0

fn push_result(var run: Together, index: Int, outcome: Outcome) Void:
	var queue = run.results.get_or(index, [])
	queue.append(outcome)
	run.results.add(index, queue)

fn pop_output(var run: Together, index: Int) Bytes:
	var queue = run.outputs.get_or(index, [])
	if queue.is_empty(): return "".to_bytes()

	first := queue[0].clone()
	run.outputs.add(index, queue.drop(1))
	return first

// Applies the records read from the results file to `run`.
fn apply(var run: Together, records: List[Record]) Void:
	for record in records:
		if record.kind == Kind.Output:
			if record.key.starts_with("f"):
				file := record.key.slice(1, record.key.length()).parse_int()
				if file.is_some(): run.fault_outputs.add(
					file.get(),
					record.payload.clone(),
				)
			else if record.key.starts_with("r"):
				file := record.key.slice(1, record.key.length()).parse_int()
				if file.is_some(): run.fault_records.add(
					file.get(),
					record.payload.clone(),
				)
			else:
				index := record.key.parse_int()

				if index.is_some():
					var queue = run.outputs.get_or(index.get(), [])
					queue.append(record.payload.clone())
					run.outputs.add(index.get(), queue)
		else if record.kind == Kind.Start:
			run.started.add(record.index, true)
			run.running_file.add(record.index, record.file)
			run.running_since.add(record.index, monotonic())
		else if record.kind == Kind.Fault:
			run.faults.add(record.file, record.message.clone())

			// The faulted file's test is no longer running.
			var gone = List[Int]()
			for index in run.running_file.keys():
				if run.running_file.get_or(index, -1) == record.file: gone.append(index)

			for index in gone:
				run.running_file.remove(index)
				run.running_since.remove(index)
		else:
			run.running_file.remove(record.index)
			run.running_since.remove(record.index)

			var outcome = Outcome(kind: "passed", nanos: record.nanos)
			outcome.printed = pop_output(run, record.index)

			if record.status == "skip":
				outcome.kind = "skipped"
				outcome.message = record.message.clone()
			else if record.status != "pass":
				outcome.message = record.message.clone()

				if record.site.is_empty():
					outcome.kind = "failed"
				else:
					outcome.kind = "rejected"
					outcome.site = record.site.clone()
					outcome.message = f"{record.message}\n  at {record.site}"

			push_result(run, record.index, outcome)

// The size of `path`, or -1 when there is no such file.
fn size_of(path: String) Int:
	info := stat(path)
	if info.is_error(): return -1

	return info.get().size

// Waits until the results file is longer than `offset` and returns its size.
fn grown(directory: String, path: String, offset: Int) Event!:
	var watcher = watch(directory)?

	while true:
		size := size_of(path)
		if size > offset: return ok(Event(kind: "records", size: size))

		event := watcher.next()?
		if event.is_none(): return error(Error("the results directory went away"))

	return ok(Event(kind: "records"))

// Everything the child writes to standard output, until it closes it.
fn drain(var out: ReadStream[Bytes]) Event!:
	var parts = BytesBuilder()

	while true:
		chunk := out.next()?
		if chunk.is_none(): break

		parts.append_bytes(chunk.get())

	return ok(Event(kind: "exit", bytes: parts.build()))

fn due(delay: Duration) Event!:
	void sleep(delay).wait()
	return ok(Event(kind: "deadline"))

fn day() Duration:
	return seconds(86400)

// Reads the records in the file beyond what `consumed` bytes already covered.
fn read_records(path: String, consumed: Int) Parsed!:
	whole := read_file(path).wait()?
	return ok(parse(whole.view(consumed, whole.length())))

// Runs the tests `indices` in one process and reports what the harness wrote.
export fn run_together(
	executable: String,
	working: String,
	options: TestOptions,
	indices: List[Int],
) Together:
	var run = Together()
	scratch := temporary("ms-test-results-")

	if scratch.is_error():
		run.ended = f"cannot create the results directory: {errno_text(scratch.err())}"
		return run

	holder := scratch.get()
	directory := holder.path()
	path := join([directory.clone(), "results"])
	var select = List[String]()
	for index in indices: select.append(f"{index}")

	var env = Map[String, String]()
	env.add("MS_TEST_SELECT", select.join(","))
	env.add("MS_TEST_RESULTS", path.clone())
	if limit := options.timeout: env.add(
		"MS_TEST_TIMEOUT_NS",
		f"{limit.to_nanoseconds()}",
	)
	if runs := options.runs: env.add("MS_TEST_RUNS", f"{runs}")
	if seed := options.seed: env.add("MS_TEST_SEED", f"{seed}")
	if fuzz := options.fuzz: env.add("MS_TEST_FUZZ_MS", f"{fuzz.to_milliseconds()}")

	started := spawn(
		executable,
		options.program.clone(),
		SpawnOptions(
			stdin: Stdio.Inherit,
			stderr: Stdio.Inherit,
			cwd: working,
			env: env,
		),
	)

	if started.is_error():
		run.ended = f"cannot start {executable}: {errno_text(started.err())}"
		return run

	var child = started.get()
	_hold := hold()
	_relay := forward_signals(child.pid())
	var out = child.stdout()

	// A test with no result past `--timeout` plus a second never waits; the process is
	// stopped. The harness fails a waiting test at the limit itself.
	var limit = day()
	if given := options.timeout: limit = given.add(seconds(1))

	bounded := options.timeout.is_some()
	var pending = List[Promise[Event]]()
	pending.append(promise(fn: drain(out)))
	pending.append(promise(fn: grown(directory, path, 0)))
	pending.append(promise(fn: due(day())))

	var consumed = 0
	var wait_ms = 0
	var seen = 0
	var stopped = false

	while true:
		woke := wait_any(pending)
		if woke.is_error(): break

		which := woke.get()
		event := pending[which].wait()

		if which == 0:
			if event.is_ok(): run.printed = event.get().bytes.clone()
			break

		if event.is_error(): break

		if which == 1:
			batch := read_records(path, consumed)

			if batch.is_ok():
				apply(run, batch.get().records)
				consumed += batch.get().used
				seen = event.get().size

			pending[1] = promise(fn: grown(directory, path, seen))
		else:
			stopped = true
			for index in run.running_since.keys():
				if not run.timed_out.contains(index): run.timed_out.append(index)
			child.kill()

		// The next look is due when the oldest running test that has not been stopped
		// reaches its limit.
		if bounded and not stopped:
			var soonest = day().to_nanoseconds()
			var any = false

			for index in run.running_since.keys():
				age := monotonic().difference(
					run.running_since.get(index).get()
				).to_nanoseconds()
				left := limit.to_nanoseconds() - age

				if not any or left < soonest:
					soonest = left
					any = true

			wait_ms = (if any: soonest else: day().to_nanoseconds()) / 1000000 + 1
			pending[2] = promise(fn: due(milliseconds(wait_ms)))

	finished := child.wait()

	if not run.timed_out.is_empty():
		run.ended = "was stopped because a test timed out"
	else if finished.is_error():
		run.ended = errno_text(finished.err())
	else if finished.get() < 0:
		run.ended = "was terminated by a signal"
	else:
		run.ended = f"exited with status {finished.get()}"

	// Anything the harness wrote after the last wake.
	last := read_records(path, consumed)
	if last.is_ok(): apply(run, last.get().records)
	for index in run.running_file.keys(): run.running.append(index)
	return run
