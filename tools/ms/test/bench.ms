// `ms bench`: each bench runs in its own process under the driver in
// `@std/test/bench.ms`, which writes one `MSBENCH {json}` line of per-iteration
// statistics to standard output. Status 1 means the bench returned an error, whose
// message and source site the process wrote to the file `MS_FAULT_RECORD` names.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	promise from "@std/concurrency/promise.ms",
	JsonValue, parse from "@std/data/json.ms",
	ReadStream, stderr from "@std/io/io.ms",
	read_file, temporary from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",
	nanoseconds from "@std/time.ms",

	errno_text from "../errno.ms",
	decode_written, from_text, is_fault_status from "./fault.ms",
	debug_duration, format_ns, round_count from "./format.ms",
	TestOptions from "./options.ms",
	Outcome from "./supervise.ms",
)

MARKER := "MSBENCH "

// The work counters of a bench's statistics: the numbers that do not depend on machine
// load, so a baseline comparison on them does not flake. Times are never compared.
fn work_counters() List[String]:
	return [
		"mir_ops", "allocations", "allocated_bytes", "list_copies", "list_copy_bytes",
		"string_clones", "string_clone_bytes"
	]

// Everything the child writes to one of its pipes.
fn collect(var pipe: ReadStream[Bytes]) Bytes!:
	var parts = BytesBuilder()

	while true:
		chunk := pipe.next()?
		if chunk.is_none(): break

		parts.append_bytes(chunk.get())

	return ok(parts.build())

// The statistics object of the `MSBENCH` line a bench driver wrote.
export fn measurement(printed: Bytes) JsonValue?:
	var found: JsonValue? = none

	for line in printed.decode_utf8().get_or("").lines():
		if mark := line.cut_prefix(MARKER):
			parsed := parse(mark)
			if parsed.is_ok(): found = parsed.get()

	return found

fn number(stats: JsonValue, key: String) Float:
	if member := stats.get(key): return member.as_float().get_or(0.0)
	return 0.0

fn count(stats: JsonValue, key: String) Int:
	if member := stats.get(key): return member.as_int().get_or(0)
	return 0

fn has(stats: JsonValue, key: String) Bool:
	return stats.get(key).is_some()

// The one-line summary of a bench's statistics.
export fn describe_stats(stats: JsonValue) String:
	var ops = ""
	if number(stats, "mir_ops") > 0.0: ops = f"; {round_count(number(stats, "mir_ops"))} MIR ops"

	var work = ""
	if has(stats, "allocations"):
		work = f"{ops}; {round_count(number(stats, "allocations"))} allocs, {round_count(number(stats, "allocated_bytes"))} bytes, {round_count(number(stats, "list_copies"))} list copies, {round_count(number(stats, "string_clones"))} string clones per op"

	iterations := count(stats, "iterations")
	samples := count(stats, "samples")
	return f"{format_ns(number(stats, "median_ns"))}/op median (min {format_ns(number(stats, "min_ns"))}, mean {format_ns(number(stats, "mean_ns"))}, max {format_ns(number(stats, "max_ns"))}, stddev {format_ns(number(stats, "stddev_ns"))}; {iterations} iterations x {samples} samples; cpu {format_ns(number(stats, "cpu_ns"))}/op{work})"

fn describe_exit(code: Int) String:
	if code < 0: return "was terminated by a signal"
	return f"exited with status {code}"

// Runs bench `index` in its own process.
export fn run_one(
	executable: String,
	working: String,
	options: TestOptions,
	index: Int,
) Outcome:
	scratch := temporary("ms-fault-")
	if scratch.is_error(): return Outcome(
		kind: "failed",
		message: errno_text(scratch.err()),
	)

	holder := scratch.get()
	record_path := join([holder.path(), "record.bin"])
	var env = Map[String, String]()
	env.add("MS_FAULT_RECORD", record_path.clone())
	if runs := options.runs: env.add("MS_TEST_RUNS", f"{runs}")
	if seed := options.seed: env.add("MS_TEST_SEED", f"{seed}")
	if fuzz := options.fuzz: env.add("MS_TEST_FUZZ_MS", f"{fuzz.to_milliseconds()}")
	if time := options.bench_time: env.add(
		"MS_BENCH_TIME_MS",
		f"{time.to_milliseconds()}",
	)
	if samples := options.bench_samples: env.add("MS_BENCH_SAMPLES", f"{samples}")
	if iterations := options.bench_iterations: env.add(
		"MS_BENCH_ITERATIONS",
		f"{iterations}",
	)

	var arguments = [f"{index}"]
	arguments.extend(options.program.clone())

	started := spawn(
		executable,
		arguments,
		SpawnOptions(stdin: Stdio.Inherit, cwd: working, env: env),
	)
	if started.is_error():
		return Outcome(
			kind: "failed",
			message: f"cannot start {executable}: {errno_text(started.err())}",
		)

	var child = started.get()
	var out = child.stdout()
	var err = child.stderr()
	printed := promise(fn: collect(out))
	errors := promise(fn: collect(err))
	finished := child.wait(options.timeout)

	if finished.is_error():
		timed := finished.err().kind == "ETIMEDOUT"
		child.kill()
		void printed.wait()
		void errors.wait()

		if timed:
			limit := options.timeout.get_or(nanoseconds(0)).to_nanoseconds()
			return Outcome(
				kind: "failed",
				message: f"timed out after {debug_duration(limit)}; the test was cancelled (use --timeout to change the limit, 0 disables it)",
			)

		return Outcome(kind: "failed", message: errno_text(finished.err()))

	shown := printed.wait().get_or("".to_bytes())
	text := errors.wait().get_or("".to_bytes()).decode_utf8().get_or("")
	code := finished.get()
	written := read_file(record_path).wait()
	record := if written.is_ok(): decode_written(written.get()) else: none

	if recorded := record:
		if recorded.test_failure:
			// The expectation's message and site are in the record; standard error
			// repeats them.
			var message = recorded.fault.message.clone()
			if recorded.has_site: message = f"{message}\n  at {recorded.site}"

			trimmed := text.trim_end_chars("\n")
			var echoed = ""
			if before := trimmed.cut_suffix(message): echoed = before
			stderr().write(echoed).get()

			var outcome = Outcome(kind: "rejected", message: message)
			if recorded.has_site: outcome.site = recorded.site.clone()
			return outcome

	if code == 0:
		stderr().write(text).get()

		if stats := measurement(shown):
			var outcome = Outcome(kind: "measured")
			outcome.stats = stats
			return outcome

		return Outcome(kind: "failed", message: "the bench reported no statistics")

	trimmed := text.trim_end_chars("\n")

	if is_fault_status(code):
		var fault = from_text(trimmed)
		if recorded := record: fault = recorded.fault.clone()

		if found := fault:
			var outcome = Outcome(kind: "faulted", message: trimmed)
			outcome.fault = found
			return outcome

	if trimmed.is_empty():
		return Outcome(kind: "failed", message: f"test process {describe_exit(code)}")

	return Outcome(kind: "failed", message: trimmed)

// Compares the work counters of every measured bench with the `--baseline` result and
// reports each one that rose by more than `--fail-over` percent (default 3). The result
// is whether any did; an unreadable baseline is an error.
export fn baseline_regressions(
	options: TestOptions,
	cases: List[Measured],
	var lines: List[String],
) Bool!:
	if options.baseline.is_empty(): return ok(false)

	path := options.baseline.clone()
	bound := options.fail_over.get_or(3.0)
	read := read_file(path).wait()
	if read.is_error():
		return error(Error(f"cannot read --baseline {path}: {errno_text(read.err())}"))

	baseline := parse(read.get().decode_utf8().get_or(""))
	if baseline.is_error():
		return error(
			Error(
				f"--baseline {path} is not the JSON that `ms bench --json` writes"
			)
		)

	earlier := baseline.get().get("benches").and_then(fn found: found.as_list())
	if earlier.is_none():
		return error(
			Error(
				f"--baseline {path} has no benches; save `ms bench --json` output"
			)
		)

	var regressed = false

	for measured in cases:
		var before: JsonValue? = none
		for candidate in earlier.get():
			if text_of(candidate, "name") == measured.name:
				if found := candidate.get("stats"): before = found.clone()

		if before.is_none():
			lines.append(f"NEW {measured.name}: not in the baseline")
			continue

		for key in work_counters():
			if not has(before.get(), key) or not has(measured.stats, key): continue

			was := number(before.get(), key)
			now := number(measured.stats, key)

			// A counter that was zero may rise by up to one before it counts.
			allowed := was * (1.0 + bound / 100.0) + (if was == 0.0: 1.0 else: 0.0)

			if now > allowed:
				regressed = true
				lines.append(
					f"REGRESSED {measured.name}: {key} {round_count(was)} -> {round_count(now)} (over the {plain(bound)}% bound)"
				)

	return ok(regressed)

fn text_of(value: JsonValue, key: String) String:
	if member := value.get(key): return member.as_string().get_or("")
	return ""

fn plain(value: Float) String:
	if whole := value.truncate_to_int():
		if whole.to_float() == value: return value.to_fixed(0)
	return value.to_string()

// A measured bench: its name and statistics.
export type Measured:
	name: String
	stats: JsonValue
