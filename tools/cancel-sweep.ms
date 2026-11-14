// Cancellation sweep (`make cancel-sweep`): cancels each test of the e2e fixtures at
// every park (await point) in turn and checks that nothing leaks. A counting runtime
// (`ms-rt` feature `stats`) numbers the parks of a process; `MS_PARK_COUNT=1` prints
// how many a test made, and
// `MS_CANCEL_AT_PARK=k` makes the k-th one report a cancellation, as if the parking task had been
// cancelled there. Each test runs alone (`--test`), since a file's tests share a
// process. The cancelled test must end with the same live blocks as the uncancelled run
// (a test that leaks without cancellation belongs to `leak-check`). A run that ends
// with more Rust heap blocks (`ms-rt rust heap at exit`) is a `heap:` hit and fails
// too. A hit must reproduce: it is re-run twice, and counts the uncancelled run itself
// shows over five runs (worker buffers vary with timing) are not hits. A cancel that
// ends the process (status 143) prints no counts and is not swept. Arguments name the
// files to sweep (default: tests/conformance/fixtures/e2e/stdlib). SWEEP_MAX_PARKS
// bounds the parks tried per test (default 64); MS names the ms to run (default
// target/release/ms). Usage: ms run tools/cancel-sweep.ms [-- files]
import (
	Promise, promise from "@std/concurrency/promise.ms",
	stdout from "@std/io/io.ms",
	arguments, change_directory, working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file, temporary from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	system_info from "@std/os/system.ms",
	seconds from "@std/time.ms",

	env, tool_ms, use_stats_runtime from "./lib.ms",
)

// One test's counts as the runtime printed them.
type Counted:
	name: String
	parks: Int
	heap: Int
	live: Int

// The tests of one `ms test` run with the parks they made and the blocks left live:
// each test prints RUN before it starts, then the runtime prints both counts as it
// ends.
fn counted(text: String) List[Counted]:
	var found = List[Counted]()
	var name = ""
	var parks = 0
	var heap = 0

	for line in text.split("\n"):
		if line.starts_with("RUN "):
			name = line.slice(4, line.length()).get("")
			parks = 0
			heap = 0
		else if line.starts_with("ms-rt parks: "):
			parks = line.slice(13, line.length()).get("").trim().parse_int().get(0)
		else if line.starts_with("ms-rt rust heap at exit: blocks="):
			heap = line.slice(
				32,
				line.length(),
			).get("").split(" ")[0].parse_int().get(0)
		else if line.starts_with("ms-rt live blocks at exit: "):
			live := line.slice(27, line.length()).get("").trim().parse_int().get(0)
			found.append(
				Counted(
					name: name.clone(),
					parks: parks,
					heap: heap,
					live: live,
				)
			)

	return found

fn has_tests(source: String) Bool:
	return source.starts_with("test \"") or source.contains("\ntest \"")

fn test_run(ms: String, file: String, filter: String, cancel_at: Int) List[Counted]:
	var settings = Map[String, String]()
	settings["MS_PARK_COUNT"] = "1"
	if cancel_at > 0: settings["MS_CANCEL_AT_PARK"] = "{cancel_at}"

	var arguments = ["test", file.clone()]
	if filter != "": arguments = arguments.concat(["--test", filter.clone()])
	if out := run(
		ms.clone(),
		arguments,
		RunOptions(timeout: seconds(120), env: settings),
	).wait(): return counted(
		out.stdout.decode_utf8().get("") + out.stderr.decode_utf8().get("")
	)

	return List[Counted]()

// The names of the tests in `file`, as `ms test --list` prints them.
fn test_names(ms: String, file: String) List[String]:
	var names = List[String]()
	if out := run(
		ms.clone(),
		["test", file.clone(), "--list"],
		RunOptions(timeout: seconds(120)),
	).wait():
		for line in out.stdout.decode_utf8().get("").split("\n"):
			if line.contains("::"): names.append(line.clone())
	return names

// Sweeps `files`: one line per cancelled run (`swept`), then one `leak:` report per run
// that left live blocks.
fn sweep(ms: String, root: String, files: List[String], most: Int) List[String]:
	var lines = List[String]()

	for f in files:
		file := "{root}/{f}"

		// A file's tests share one process, so each test is counted in a run of its
		// own.
		for name in test_names(ms.clone(), file.clone()):
			found := test_run(ms.clone(), file.clone(), name.clone(), 0)
			if found.is_empty() or found[0].name != name: continue

			base := found[0].clone()
			if base.parks == 0: continue

			last := if base.parks < most: base.parks else: most
			reference := base.clone()

			// Counts the uncancelled run shows on any of five runs are normal for this
			// test: worker threads leave buffers of timing-dependent size behind, which
			// is not a leaked frame.
			var normal_live = [reference.live]
			var normal_heap = [reference.heap]
			var ceiling = reference.heap

			for repeat in 0..4:
				for r in test_run(ms.clone(), file.clone(), base.name.clone(), 0):
					if r.name == base.name:
						normal_live.append(r.live)
						normal_heap.append(r.heap)
						if r.heap > ceiling: ceiling = r.heap

			for k in 1..last + 1:
				for hit in test_run(ms.clone(), file.clone(), base.name.clone(), k):
					lines.append("swept")

					var live = hit.live
					var heap = hit.heap
					var bad_live = not normal_live.contains(live)
					var bad_heap = heap > ceiling
					var tries = 0

					while (bad_live or bad_heap) and tries < 2:
						tries += 1

						var ran = false

						for r in test_run(
							ms.clone(),
							file.clone(),
							base.name.clone(),
							k,
						):
							ran = true

							if not normal_live.contains(r.live): live = r.live
							else: bad_live = false

							if r.heap <= ceiling: bad_heap = false
							else if r.heap < heap: heap = r.heap

						if not ran: break

					if bad_live: lines.append(
						"leak: {f} \"{hit.name}\" cancelled at park {k} of {base.parks} left {live} live blocks (uncancelled run: {reference.live})"
					)
					else if bad_heap: lines.append(
						"heap: {f} \"{hit.name}\" cancelled at park {k} of {base.parks} ended with {heap} Rust heap blocks (uncancelled runs: at most {ceiling})"
					)

	return lines

fn main() Int:
	code := use_stats_runtime()
	if code != 0: return code

	root := working_directory().get()
	var files = List[String]()
	for f in arguments(): files.append(f.clone())

	if files.is_empty():
		for f in glob(
			"tests/conformance/fixtures/e2e/stdlib",
			GlobOptions(patterns: ["*.ms"]),
		).get([]):
			path := "tests/conformance/fixtures/e2e/stdlib/{f.path}"
			if has_tests(read_file(path.clone()).wait().get().decode_utf8().get("")): files.append(
				path.clone()
			)

	ms := tool_ms(root.clone())
	scratch := temporary("ms-cancel-").get()
	change_directory(scratch.path()).get()

	var jobs = system_info().cpu_count
	if n := env("LEAK_JOBS", "").parse_int(): jobs = n
	if jobs < 1: jobs = 1

	var most = 64
	if n := env("SWEEP_MAX_PARKS", "").parse_int(): most = n

	var chunks = List[List[String]]()

	for worker in 0..jobs:
		var mine = List[String]()
		for i in 0..files.length():
			if i % jobs == worker: mine.append(files[i].clone())
		chunks.append(mine)

	var tasks = List[Promise[List[String]]]()
	for worker in 0..jobs:
		tasks.append(
			promise(
				fn: ok(
					sweep(
						ms.clone(),
						root.clone(),
						chunks[worker],
						most,
					)
				)
			)
		)

	var swept = 0
	var leaks = 0
	var heaps = 0

	for task in tasks:
		for line in task.wait().get(List[String]()):
			if line == "swept": swept += 1
			else:
				if line.starts_with("heap: "): heaps += 1
				else: leaks += 1

				print("{line}")

	change_directory(root).get()
	(
		stdout()
		.write(
			"cancel-sweep: {swept} cancelled runs, {leaks} leaking, {heaps} with extra Rust heap\n"
		)
		.get()
	)
	if leaks + heaps > 0: return 1

	return 0
