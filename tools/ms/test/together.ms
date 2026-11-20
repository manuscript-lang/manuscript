// What one run of the test executable reported, built from the records it appended to
// its results file.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Kind, Record, parse from "./records.ms",
)

export enum Status:
	Passed
	Skipped
	// The test failed without naming where.
	Failed
	// An expectation failed: `site` is `file:line:column`.
	Rejected

export type Outcome:
	status: Status
	message: String = ""
	site: String = ""
	nanos: Int = 0
	// What the test printed.
	printed: Bytes = "".to_bytes()

export type Together:
	// Each test's outcome, by position in the listing.
	results: Map[Int, Outcome] = Map[Int, Outcome]()
	// Tests that started, in order.
	started: List[Int] = []
	// Files whose test faulted, by file number, with the fault message.
	faults: Map[Int, String] = Map[Int, String]()
	// A faulted file's fault record (`ms_rt_abi` record bytes), by file number.
	fault_records: Map[Int, Bytes] = Map[Int, Bytes]()
	// A faulted file's output since its last result, by file number.
	fault_outputs: Map[Int, Bytes] = Map[Int, Bytes]()
	// Tests that started and have not reported, with the file each runs in.
	running: Map[Int, Int] = Map[Int, Int]()
	// Output received for a test whose result has not arrived.
	output: Map[Int, Bytes] = Map[Int, Bytes]()
	// Tests stopped with the process for running past `--timeout`.
	timed_out: List[Int] = []
	// How the process ended.
	ended: String = ""
	// What the process wrote to standard output.
	printed: Bytes = "".to_bytes()

fn status_of(word: String, site: String) Status:
	if word == "pass": return Status.Passed
	if word == "skip": return Status.Skipped
	if site.is_empty(): return Status.Failed

	return Status.Rejected

// Records `record` in `run`.
fn apply(var run: Together, record: Record) Void:
	if record.kind == Kind.Start:
		run.started.append(record.index)
		run.running.add(record.index, record.file)
	else if record.kind == Kind.Fault:
		run.faults.add(record.file, record.message.clone())

		// The faulted file's test is no longer running.
		var gone = List[Int]()
		for entry in run.running.entries():
			if entry.value == record.file: gone.append(entry.key)
		for index in gone: run.running.remove(index)
	else if record.kind == Kind.Result:
		var printed = "".to_bytes()
		if held := run.output.get(record.index): printed = held.clone()
		run.output.remove(record.index)
		run.running.remove(record.index)
		run.results.add(
			record.index,
			Outcome(
				status: status_of(record.status, record.site),
				message: record.message.clone(),
				site: record.site.clone(),
				nanos: record.nanos,
				printed: printed,
			),
		)
	else:
		key := record.key

		if key.starts_with("f"):
			if file := key.slice(1, key.length()).parse_int():
				run.fault_outputs.add(file, record.payload.clone())
		else if key.starts_with("r"):
			if file := key.slice(1, key.length()).parse_int():
				run.fault_records.add(file, record.payload.clone())
		else if index := key.parse_int():
			run.output.add(index, record.payload.clone())

// Folds the records in the first `data.length()` bytes of the results file that
// `offset` bytes have not been read yet into `run`, and returns the new offset.
export fn absorb(var run: Together, data: Bytes, offset: Int) Int:
	if offset >= data.length(): return offset

	parsed := parse(data.view(offset, data.length()))
	for record in parsed.records: apply(run, record)
	return offset + parsed.used

test "records fold into results, faults and running tests":
	var run = Together()
	text := "\u{1}MSSTART 0 0\n\u{1}MSSTART 1 1\n\u{1}MSOUT 0 2\nhi\n\u{1}MSTEST 0 pass 90\u{1}\u{1}\n\u{1}MSFAULT 1\u{1}boom\n"
	data := text.to_bytes()
	used := absorb(run, data, 0)
	used | expect_equal(expected: data.length())?
	run.started | expect_equal(expected: [0, 1])?
	run.results.get(0).get().status | expect_equal(expected: Status.Passed)?
	run.results.get(0).get().printed.length() | expect_equal(expected: 2)?
	run.faults.get(1).get() | expect_equal(expected: "boom")?
	run.running.length() | expect_equal(expected: 0)?

test "a later read resumes where the last one stopped":
	var run = Together()
	first := "\u{1}MSSTART 2 0\n\u{1}MSTEST 2 fail 5\u{1}bad\u{1}a.ms:3:1\n"
	second := first + "\u{1}MSSTART 3 0\n"
	mid := absorb(run, first.to_bytes(), 0)
	run.results.get(2).get().status | expect_equal(expected: Status.Rejected)?
	run.results.get(2).get().site | expect_equal(expected: "a.ms:3:1")?
	(
		absorb(run, second.to_bytes(), mid) | expect_equal(
			expected: second.to_bytes().length()
		)?
	)
	run.running.length() | expect_equal(expected: 1)?
