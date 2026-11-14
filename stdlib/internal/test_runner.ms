import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	Instant, monotonic from "@std/time.ms",

	msstd_process_environment_map from "@std/internal/env.ms",
	msrt_test_capture_current,
	msrt_test_capture_fault,
	msrt_test_capture_free,
	msrt_test_capture_new,
	msrt_test_capture_set,
	msrt_test_capture_take,
	msrt_test_deadline,
	msrt_test_record from "@std/internal/test.ms",
)

/*
The entry `ms test` builds calls `run_test_files` with one runner per test file; programs
do not. Files run at once, each in its own promise, and a file's tests run in order. A
fault in a test ends its file: the runner names the test that was running and the file's
later tests are not run.

`MS_TEST_SELECT` lists the test indices to run, comma-separated (all when unset);
`MS_TEST_PARALLEL=1` runs the files one at a time; each test's waits (and its hooks') fail
with ETIMEDOUT after `MS_TEST_TIMEOUT_NS`, as a promise timeout does. Records go to the file
`MS_TEST_RESULTS` names, one line each, so standard output stays the tests' own:
`\u{1}MSSTART <index> <file>` when a test starts (files numbered in the order given), then
`\u{1}MSTEST <index> <status> <nanoseconds>\u{1}<message>\u{1}<site>` when it ends (status
pass, fail or skip), or `\u{1}MSFAULT <file>\u{1}<message>` when a test of that file faulted.
A test's standard output comes before its result as `\u{1}MSOUT <index> <bytes>`, a newline,
the output and a newline; a faulted file's last output as `\u{1}MSOUT f<file> <bytes>` and
its fault record (`ms_rt_abi::record`) as `\u{1}MSOUT r<file> <bytes>`.
*/
export fn run_test_files(files: List[fn(List[Int], String) Unit]) Int:
	environment := msstd_process_environment_map().get(Map[String, String]())
	results := environment.get_or("MS_TEST_RESULTS", "")
	var selected = List[Int]()
	for text in environment.get_or("MS_TEST_SELECT", "").split(","):
		if text.length() > 0:
			selected.append(text.parse_int().get(-1))

	if environment.get_or("MS_TEST_PARALLEL", "") == "1":
		for position in 0..files.length():
			run_file(files, position, selected, results)
		return 0

	run_range(files, 0, files.length(), selected, results)
	return 0

// Runs files[low..high] at once: the upper half in a promise, the lower half here. Each
// promise reads its captures in place, and every one ends before the frame that made
// it.
fn run_range(
	files: List[fn(List[Int], String) Unit],
	low: Int,
	high: Int,
	selected: List[Int],
	results: String,
) Unit:
	if high - low <= 0: return unit

	if high - low == 1:
		run_file(files, low, selected, results)
		return unit

	middle := (low + high) / 2
	upper := promise(
		fn: ok(run_range(files, middle, high, selected, results)),
		options: PromiseOptions(placement: Placement.Spread)
	)
	run_range(files, low, middle, selected, results)
	upper.wait().get()

// Runs one file's tests in a promise, so a fault ends only that file.
fn run_file(
	files: List[fn(List[Int], String) Unit],
	position: Int,
	selected: List[Int],
	results: String,
) Unit:
	capture := msrt_test_capture_new()
	result := promise(
		fn: run_captured(files, position, selected, results, capture),
		options: PromiseOptions(placement: Placement.Spread)
	).wait()

	if result.is_error():
		output(results, "f{position}", msrt_test_capture_take(capture))
		output(results, "r{position}", msrt_test_capture_fault(capture))
		record(results, "\u{1}MSFAULT {position}\u{1}{fault_message(result.err())}\n")

	msrt_test_capture_free(capture)

// Runs file `position` with its standard output, and its promises', going to `capture`.
fn run_captured(
	files: List[fn(List[Int], String) Unit],
	position: Int,
	selected: List[Int],
	results: String,
	capture: Int,
) Unit!:
	msrt_test_capture_set(capture)
	files[position](selected, results)
	return ok(unit)

// The fault report (message and the test's frames, without the runner's) on one record
// line: newlines become U+0002.
fn fault_message(cause: Error) String:
	report := cause.details.get_or("report", cause.message)
	var kept = List[String]()

	for text in report.trim_end().split("\n"):
		if text.starts_with("  at @std/internal/test_runner.ms:"): break

		kept.append(text.clone())

	return kept.join("\u{2}")

// Runs a file's tests without a fixture.
export fn run_plain_file(
	file: Int,
	tests: List[fn() Unit!],
	indices: List[Int],
	selected: List[Int],
	results: String,
) Unit:
	for position in 0..tests.length():
		index := indices[position]
		if not chosen(selected, index): continue

		start(results, file, index)

		started := monotonic()
		outcome := tests[position]()
		report(results, index, started, outcome)

// Owns a file's fixture; closing it runs `after_each` when a test was running and then
// `after_all`, so a fault in a test still tears the fixture down.
type FixtureScope[F]:
	fixture: F
	after_each: fn(var F) Unit!
	after_all: fn(var F) Unit!
	in_test: Bool

fn var FixtureScope[F].close() Unit!:
	if self.in_test:
		self.in_test = false
		self.after_each(var self.fixture)?

	return self.after_all(var self.fixture)

// Runs a file's tests on one fixture: `make` and `before_all` once, `before_each` and
// `after_each` around each test, then `after_all`. A hook's error fails (or, kind ESKIP,
// skips) the tests it guards.
export fn run_fixture_file[F](
	file: Int,
	make: fn() F,
	before_all: fn(var F) Unit!,
	before_each: fn(var F) Unit!,
	after_each: fn(var F) Unit!,
	after_all: fn(var F) Unit!,
	tests: List[fn(var F) Unit!],
	indices: List[Int],
	selected: List[Int],
	results: String
) Unit:
	var scope = FixtureScope[F](
		fixture: make(),
		after_each: after_each,
		after_all: after_all,
		in_test: false,
	)
	started := monotonic()
	msrt_test_deadline(true)

	setup := before_all(var scope.fixture)

	for position in 0..tests.length():
		index := indices[position]
		if not chosen(selected, index): continue

		start(results, file, index)

		if setup.is_error():
			report(results, index, started, error(setup.err().clone()))
			continue

		began := monotonic()
		scope.in_test = true

		var outcome = before_each(var scope.fixture)
		if not outcome.is_error():
			outcome = tests[position](var scope.fixture)
		scope.in_test = false

		teardown := scope.after_each(var scope.fixture)
		if teardown.is_error() and not outcome.is_error():
			outcome = error(teardown.err().clone())
		report(results, index, began, outcome)

	msrt_test_deadline(true)

fn chosen(selected: List[Int], index: Int) Bool:
	return selected.is_empty() or selected.contains(index)

fn start(results: String, file: Int, index: Int) Unit:
	record(results, "\u{1}MSSTART {index} {file}\n")
	msrt_test_deadline(true)

fn report(results: String, index: Int, started: Instant, outcome: Unit!) Unit:
	msrt_test_deadline(false)
	output(results, "{index}", msrt_test_capture_take(msrt_test_capture_current()))

	nanos := (monotonic() - started).nanos

	if not outcome.is_error():
		line(results, index, "pass", nanos, "", "")
		return unit

	cause := outcome.err()

	if cause.kind == "ESKIP":
		line(results, index, "skip", nanos, cause.message, "")
		return unit

	line(results, index, "fail", nanos, cause.message, cause.details.get_or("site", ""))

fn line(
	results: String,
	index: Int,
	status: String,
	nanos: Int,
	message: String,
	site: String,
) Unit:
	record(results, "\u{1}MSTEST {index} {status} {nanos}\u{1}{message}\u{1}{site}\n")

// Records `text` as the output of `key` (a test index, or `f` and a file number).
fn output(results: String, key: String, text: String) Unit:
	if text.byte_length() == 0: return unit

	record(results, "\u{1}MSOUT {key} {text.byte_length()}\n{text}\n")

fn record(results: String, text: String) Unit:
	msrt_test_record(results, text)
