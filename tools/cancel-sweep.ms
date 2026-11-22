// Cancellation sweep (`make cancel-sweep`): cancels each test of the e2e fixtures at
// every park (await point) in turn and checks that nothing leaks. A counting runtime
// (`ms-rt` feature `stats`) numbers the parks of a process; `MS_PARK_COUNT=1` prints
// how many a test made, and
// `MS_CANCEL_AT_PARK=k` makes the k-th one report a cancellation, as if the parking task had been
// cancelled there. Each test runs alone (`--test`), since a file's tests share a
// process. The cancelled test must end with the same live blocks as the uncancelled run
// (a test that leaks without cancellation belongs to `leak-check`). A run that ends
// with more Rust heap blocks (`ms-rt rust heap at exit`) is a `heap:` hit and fails
// too; the heap is compared on one scheduler thread (`MS_THREADS=1`), where it is
// exact, since which threads served is timing. A live-block hit must reproduce: it is
// re-run twice, and live counts the uncancelled run itself shows over five runs are not
// hits. A cancel that ends the process (status 143) prints no counts and is not swept,
// but one killed by a signal is a hit. Arguments name the files to sweep (default:
// tests/conformance/fixtures/e2e/stdlib). SWEEP_MAX_PARKS bounds the parks tried per
// test (default 64); MS names the ms to run (default target/release/ms). Usage: ms run
// tools/cancel-sweep.ms [-- files]
import (
	Promise, promise from "@std/concurrency/promise.ms",
	stdout from "@std/io/io.ms",
	arguments, change_directory, working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file, temporary, write_file from "@std/os/fs.ms",
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
	failed: Bool

// The tests of one `ms test` run with the parks they made and the blocks left live:
// each test prints RUN before it starts, then the runtime prints both counts as it
// ends.
fn counted(text: String) List[Counted]:
	var found = List[Counted]()
	var name = ""
	var parks = 0
	var heap = 0
	var failed = false

	for line in text.split("\n"):
		if line.starts_with("RUN "):
			name = line.slice(4, line.length())
			parks = 0
			heap = 0
			failed = false
		else if line.starts_with("FAIL "):
			failed = true

			// A crash prints no counts: report it as a run with no live count.
			if line.contains("terminated by signal"): found.append(
				Counted(
					name: name.clone(),
					parks: 0,
					heap: 0,
					live: -1,
					failed: true,
				)
			)
		else if line.starts_with("ms-rt parks: "):
			parks = line.slice(13, line.length()).trim().parse_int().get_or(0)
		else if line.starts_with("ms-rt rust heap at exit: blocks="):
			heap = line.slice(32, line.length()).split(" ")[0].parse_int().get_or(0)
		else if line.starts_with("ms-rt live blocks at exit: "):
			live := line.slice(27, line.length()).trim().parse_int().get_or(0)
			found.append(
				Counted(
					name: name.clone(),
					parks: parks,
					heap: heap,
					live: live,
					failed: failed,
				)
			)

	return found

fn has_tests(source: String) Bool:
	return source.starts_with("test \"") or source.contains("\ntest \"")

fn test_run(
	ms: String,
	file: String,
	filter: String,
	cancel_at: Int,
	threads: Int,
) List[Counted]:
	var settings = Map[String, String]()
	settings["MS_PARK_COUNT"] = "1"
	if threads > 0: settings["MS_THREADS"] = f"{threads}"
	if cancel_at > 0: settings["MS_CANCEL_AT_PARK"] = f"{cancel_at}"

	var arguments = ["test", file.clone()]
	if filter != "": arguments = arguments.concat(["--test", filter.clone()])
	if out := run(
		ms.clone(),
		arguments,
		RunOptions(timeout: seconds(120), env: settings),
	).wait(): return counted(
		out.stdout.decode_utf8().get_or("") + out.stderr.decode_utf8().get_or(
			""
		)
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
		for line in out.stdout.decode_utf8().get_or("").split("\n"):
			if line.contains("::"): names.append(line.clone())
	return names

// The Rust heap check of one test on a single scheduler thread, where no thread's
// leftovers vary: the uncancelled run must repeat its count exactly, and a cancelled
// run may not end with more (a failing run holds `report` more).
fn heap_sweep(
	ms: String,
	file: String,
	name: String,
	most: Int,
	report: Int,
) List[String]:
	var lines = List[String]()
	var base = Counted(name: "", parks: 0, heap: 0, live: 0, failed: false)
	for r in test_run(ms.clone(), file.clone(), name.clone(), 0, 1):
		if r.name == name: base = r.clone()
	if base.parks == 0: return lines

	for repeat in 0..2:
		for r in test_run(ms.clone(), file.clone(), name.clone(), 0, 1):
			if r.name == name and r.heap != base.heap: return [
				f"heap: {file} \"{name}\" ends with {r.heap} and {base.heap} Rust heap blocks on one thread without any cancel: the baseline is not deterministic"
			]

	last := if base.parks < most: base.parks else: most

	for k in 1..last + 1:
		for hit in test_run(ms.clone(), file.clone(), name.clone(), k, 1):
			var heap = hit.heap
			var tries = 0

			while heap > base.heap + (if hit.failed: report else: 0) and tries < 2:
				tries += 1
				for r in test_run(ms.clone(), file.clone(), name.clone(), k, 1):
					if r.heap < heap: heap = r.heap

			if heap > base.heap + (if hit.failed: report else: 0): lines.append(
				f"heap: {file} \"{name}\" cancelled at park {k} of {base.parks} ended with {heap} Rust heap blocks on one thread (uncancelled run: {base.heap})"
			)

	return lines

// Sweeps `files`: one line per cancelled run (`swept`), then one `leak:` report per run
// that left live blocks.
fn sweep(
	ms: String,
	root: String,
	files: List[String],
	most: Int,
	report: Int,
) List[String]:
	var lines = List[String]()

	for f in files:
		file := f"{root}/{f}"

		// A file's tests share one process, so each test is counted in a run of its
		// own.
		for name in test_names(ms.clone(), file.clone()):
			found := test_run(ms.clone(), file.clone(), name.clone(), 0, 0)
			if found.is_empty() or found[0].name != name: continue

			base := found[0].clone()
			if base.parks == 0: continue

			last := if base.parks < most: base.parks else: most
			reference := base.clone()

			// Live counts the uncancelled run shows on any of five runs are normal for
			// this test.
			var normal_live = [reference.live]
			for repeat in 0..4:
				for r in test_run(ms.clone(), file.clone(), base.name.clone(), 0, 0):
					if r.name == base.name: normal_live.append(r.live)

			// The Rust heap is compared on one scheduler thread (`heap_sweep`): with
			// several, which threads served a request (and kept per-thread buffers) is
			// timing, so five uncancelled runs can agree by chance and a cancelled run
			// differ by a block.
			lines = lines.concat(
				heap_sweep(
					ms.clone(),
					f.clone(),
					base.name.clone(),
					most,
					report,
				)
			)

			for k in 1..last + 1:
				for hit in test_run(ms.clone(), file.clone(), base.name.clone(), k, 0):
					lines.append("swept")

					if hit.live < 0:
						lines.append(
							f"leak: {f} \"{hit.name}\" cancelled at park {k} of {base.parks} crashed with a signal"
						)
						continue

					var live = hit.live
					var bad_live = not normal_live.contains(live)
					var tries = 0

					while bad_live and tries < 2:
						tries += 1

						var ran = false

						for r in test_run(
							ms.clone(),
							file.clone(),
							base.name.clone(),
							k,
							0,
						):
							ran = true

							if not normal_live.contains(r.live): live = r.live
							else: bad_live = false

						if not ran: break

					if bad_live: lines.append(
						f"leak: {f} \"{hit.name}\" cancelled at park {k} of {base.parks} left {live} live blocks (uncancelled run: {reference.live})"
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
		).get_or([]):
			path := f"tests/conformance/fixtures/e2e/stdlib/{f.path}"
			if has_tests(read_file(path.clone()).wait().get().decode_utf8().get_or("")): files.append(
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

	// The Rust heap blocks a fault leaves at exit: a failing test ends with that many
	// more than one that passes.
	pass_file := f"{scratch.path()}/pass.ms"
	fault_file := f"{scratch.path()}/fault.ms"
	write_file(pass_file.clone(), "test \"p\":\n\tprint(\"ok\")\n", true).wait().get()
	write_file(
		fault_file.clone(),
		"fn nothing() Int?:\n\treturn none\n\ntest \"f\":\n\tprint(f\"{nothing().get()}\")\n",
		true,
	).wait().get()

	var report = 0
	for a in test_run(ms.clone(), fault_file.clone(), "", 0, 0):
		for b in test_run(ms.clone(), pass_file.clone(), "", 0, 0):
			if a.heap > b.heap: report = a.heap - b.heap

	var chunks = List[List[String]]()

	for worker in 0..jobs:
		var mine = List[String]()
		for i in 0..files.length():
			if i % jobs == worker: mine.append(files[i].clone())
		chunks.append(mine)

	var tasks = List[Promise[List[String]]]()
	for worker in 0..jobs:
		ms_copy := ms.clone()
		root_copy := root.clone()
		chunk := chunks[worker].clone()
		most_now := most
		report_now := report
		tasks.append(
			promise(
				fn: ok(
					sweep(
						ms_copy,
						root_copy,
						chunk,
						most_now,
						report_now,
					)
				)
			)
		)

	var swept = 0
	var leaks = 0
	var heaps = 0

	for task in tasks:
		for line in task.wait().get_or(List[String]()):
			if line == "swept": swept += 1
			else:
				if line.starts_with("heap: "): heaps += 1
				else: leaks += 1

				print(f"{line}")

	change_directory(root).get()
	(
		stdout()
		.write(
			f"cancel-sweep: {swept} cancelled runs, {leaks} leaking, {heaps} with extra Rust heap\n"
		)
		.get()
	)
	if leaks + heaps > 0: return 1

	return 0
