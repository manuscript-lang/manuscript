// Leak sweep (`make leak-check`): runs the programs of the conformance corpus that finish normally against a runtime
// built with allocation counters (`ms-rt` feature `stats`), which prints the count of live heap blocks at exit. A
// correct program frees everything it allocated, so any nonzero count is a leak. Faulting and rejected programs print
// no count and are skipped. The `test` blocks of tests/e2e/testdata run the same way, one count per test. Arguments name
// the files to sweep instead; a file with test blocks is run with `ms test`.
// MS names the ms that runs the programs (default target/release/ms).
// Usage: ms run tools/leak-check.ms [-- files]
import (
	Promise, promise from "@std/concurrency/promise.ms",
	arguments, change_directory, working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file, temporary from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	system_info from "@std/os/system.ms",
	seconds from "@std/time.ms",

	env, tool_ms, use_stats_runtime from "./lib.ms",
)

// The live block counts the runtime printed on standard error; a program that starts child
// processes prints one per process, and their sum is what leaked. Empty when none was printed.
fn live_blocks(text: String) List[Int]:
	var counts = List[Int]()
	for line in text.split("\n"):
		if line.starts_with("ms-rt live blocks at exit: "):
			if n := line.slice(27, line.length()).get("").trim().parse_int(): counts.append(
				n
			)
	return counts

// The tests of one `ms test` run that left live blocks, as "name: count" lines: each test prints RUN before it
// starts, and the runtime prints its count as the process exits or after the test.
fn leaking_tests(text: String) List[String]:
	var leaks = List[String]()
	var current = ""

	for line in text.split("\n"):
		if line.starts_with("RUN "): current = line.slice(4, line.length()).get("")
		else if line.starts_with("ms-rt live blocks at exit: "):
			n := line.slice(27, line.length()).get("").trim().parse_int().get(0)
			if n != 0: leaks.append("{current}: {n}")

	return leaks

fn has_tests(source: String) Bool:
	return source.starts_with("test \"") or source.contains("\ntest \"")

// Sweeps `files` and returns one line per swept program (`swept`), followed by one report per
// leak that starts with `leak:`.
fn sweep(ms: String, root: String, files: List[String]) List[String]:
	var lines = List[String]()

	for f in files:
		absolute := "{root}/{f}"
		source := read_file(absolute.clone()).wait().get().decode_utf8().get("")

		if has_tests(source):
			if out := run(
				ms.clone(), ["test", absolute.clone()],
				RunOptions(timeout: seconds(600))
			).wait():
				found := leaking_tests(out.stderr.decode_utf8().get(""))
				lines.append("swept")
				if not found.is_empty(): lines.append(
					"leak: {absolute}\n  {found.join("\n  ")}"
				)

			continue

		if out := run(
			ms.clone(), ["run", absolute.clone()], RunOptions(timeout: seconds(60))
		).wait():
			counts := live_blocks(out.stderr.decode_utf8().get(""))
			if counts.is_empty(): continue

			lines.append("swept")

			total := counts.fold(0, fn(a: Int, b: Int) Int: a + b)
			if total != 0: lines.append("leak: {absolute} left {total} live blocks")

	return lines

fn main() Int:
	code := use_stats_runtime()
	if code != 0: return code

	root := working_directory().get()
	var files = List[String]()
	for f in arguments(): files.append(f.clone())

	if files.is_empty():
		for dir in [
			"tests/conformance/fixtures/fuzz/run", "tests/conformance/fixtures/e2e",
			"tests/conformance/fixtures/examples"
		]:
			for f in glob(dir, GlobOptions(patterns: ["**/*.ms"])).get([]):
				path := "{dir}/{f.path}"
				if read_file(path.clone()).wait().get().decode_utf8().get(
					""
				).contains("fn main"): files.append(path.clone())

	if files.is_empty():
		for f in glob("tests/e2e/testdata", GlobOptions(patterns: ["**/*.ms"])).get([]):
			path := "tests/e2e/testdata/{f.path}"
			if has_tests(read_file(path.clone()).wait().get().decode_utf8().get("")): files.append(
				path.clone()
			)

	ms := tool_ms(root.clone())
	scratch := temporary("ms-leak-").get()
	change_directory(scratch.path()).get()

	// Each program runs in its own process, so the sweep splits across one worker per CPU
	// (LEAK_JOBS overrides). Workers share the scratch directory, which is only the working
	// directory of the child processes.
	var jobs = system_info().cpu_count
	if n := env("LEAK_JOBS", "").parse_int(): jobs = n
	if jobs < 1: jobs = 1

	// A promise reads its captures until it is dropped, so the chunks outlive the loop that starts them.
	var chunks = List[List[String]]()

	for worker in 0..jobs:
		var mine = List[String]()
		for i in 0..files.length():
			if i % jobs == worker: mine.append(files[i].clone())
		chunks.append(mine)

	var tasks = List[Promise[List[String]]]()
	for worker in 0..jobs:
		tasks.append(promise(fn: ok(sweep(ms.clone(), root.clone(), chunks[worker]))))

	var swept = 0
	var leaks = 0

	for task in tasks:
		for line in task.wait().get(List[String]()):
			if line == "swept": swept += 1
			else:
				leaks += 1
				print("{line}")

	change_directory(root).get()
	print("swept {swept} programs, {leaks} leaking")

	if swept == 0:
		print("no program reported a live block count")
		return 1

	if leaks > 0: return 1

	return 0
