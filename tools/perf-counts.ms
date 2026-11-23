// Instruction-count gate (`make perf-counts`): builds the small suite and guard
// programs, runs each under callgrind and compares the instructions it executed with
// the committed numbers in bench/perf/counts.txt. Instruction counts do not depend on
// machine load, so a few percent is a real change, unlike a wall-clock time on a shared
// runner. A count more than BOUND percent above the committed one fails (default 3); a
// count that fell by more than BOUND percent is reported so the file can be refreshed.
// `-- --update` rewrites the file with the measured counts. MS names the ms to measure
// (default .artifacts/build/ci/src/cli/ms); PERF_COUNTS_BOUND overrides the bound.
// Needs valgrind on the PATH. Usage: ms run tools/perf-counts.ms [-- --update]
import (
	stdout from "@std/io/io.ms",
	arguments, working_directory from "@std/os/env.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	env, tool_ms from "./lib.ms",
)

// Programs of bench/perf/suite measured, one per area that a change to generated code,
// the runtime or the strings library would move.
PROGRAMS := ["interp", "strings", "lz", "graph"]
// Small programs of bench/perf/guards, one per recent speed fix (signature tables,
// regex prefilter, image codecs, fused chains, map probes, scope-end close, string
// append). Each is counted as
// `guard-<name>`.
GUARDS := [
	"crypto", "regex", "image", "chains", "maps", "cleanup", "resultvar", "csvcells",
	"mapinsert", "http-request", "splitfirst", "splitbuf", "findshort", "append",
	"strcmp", "iterchain"
]
// Guards that take their own path as the argument (they start themselves as a child,
// which valgrind does not follow, so only the part under test is counted).
SELF_PATH := ["guard-http-request", "guard-http-request-small"]
// Guards that are another shape of a guard above: name, source directory, argument
// naming the shape.
SHAPES := [["http-request-small", "http-request", "small"]]
// Counts held to 1 percent instead of the default: most of their instructions are the
// per-request path itself, which a few hundred more instructions per request would
// otherwise hide.
TIGHT := ["guard-http-request", "guard-http-request-small"]
COUNTS := "bench/perf/counts.txt"

fn say(text: String) Void:
	stdout().write(text.clone()).get()

// Instructions `program` executed under callgrind, or -1 when it did not run.
fn count(program: String, out_file: String, own_path: Bool, shape: String) Int:
	var command = [
		"--tool=callgrind",
		f"--callgrind-out-file={out_file}",
		program.clone(),
	]
	if own_path: command.append(program.clone())
	if shape != "": command.append(shape.clone())

	if out := run("valgrind", command, RunOptions(timeout: seconds(600))).wait():
		for line in (out.stderr.decode_utf8() or "").split("\n"):
			if at := line.index_of("Collected : "):
				digits := line.slice(at + 12, line.length()).trim()
				return digits.parse_int() or (-1)

	return -1

// The committed counts: one `name instructions` pair per line.
fn committed(path: String) Map[String, Int]:
	var known = Map[String, Int]()
	text := read_file(path).wait().get_or("".to_bytes()).decode_utf8() or ""

	for line in text.split("\n"):
		parts := line.trim().split(" ")
		if parts.length() != 2 or parts[0].starts_with("#"): continue

		known[parts[0].clone()] = parts[1].parse_int() or 0

	return known

fn main() Int:
	root := working_directory().get()
	ms := tool_ms(root.clone())
	bound := env("PERF_COUNTS_BOUND", "3").parse_int() or 3
	update := arguments().contains("--update")
	path := f"{root}/{COUNTS}"
	known := committed(path.clone())
	scratch := temporary("ms-perf-counts-").get()
	var failures = 0
	var report = "# Instructions executed under callgrind by `make perf-counts`; refresh with `ms run tools/perf-counts.ms -- --update`.\n"
	var targets: List[List[String]] = []
	for name in PROGRAMS: targets.append(
		[name.clone(), f"{root}/bench/perf/suite/{name}/main.ms", ""]
	)
	for name in GUARDS: targets.append(
		[f"guard-{name}", f"{root}/bench/perf/guards/{name}/main.ms", ""]
	)
	for shape in SHAPES: targets.append(
		[
			f"guard-{shape[0]}",
			f"{root}/bench/perf/guards/{shape[1]}/main.ms",
			shape[2].clone(),
		]
	)

	for target in targets:
		name := target[0].clone()
		source := target[1].clone()
		shape := target[2].clone()
		binary := f"{scratch.path()}/{name}"
		built := run(
			ms.clone(),
			["build", source, "-o", binary.clone()],
			RunOptions(timeout: seconds(600)),
		).wait()

		if built.is_error():
			say(f"fail: {name} did not build\n")
			failures += 1
			continue

		now := count(
			binary.clone(),
			f"{scratch.path()}/{name}.out",
			SELF_PATH.contains(name),
			shape.clone(),
		)

		if now < 0:
			say(f"fail: {name} did not run under valgrind\n")
			failures += 1
			continue

		report += f"{name} {now}\n"

		before := known.get_or(name, 0)

		if before == 0:
			say(f"{name}: {now} (no committed count)\n")
			if not update: failures += 1
			continue

		limit := if TIGHT.contains(name): 1 else: bound
		tenths := (now - before) * 1000 / before
		say(f"{name}: {now} against {before} ({tenths / 10}.{tenths.abs() % 10}%)\n")

		if tenths > limit * 10:
			failures += 1
			say(
				f"fail: {name} executes more than {limit}% more instructions than the committed count; find the change that made it slower, or refresh {COUNTS} when the cost is deliberate\n"
			)
		else if tenths < -limit * 10:
			say(f"note: {name} got faster; refresh {COUNTS} with --update\n")

	if update:
		write_file(path, report, true).wait().get()
		say(f"wrote {COUNTS}\n")
		return 0

	if failures > 0: return 1

	return 0
