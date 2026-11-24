// Scheduler stress run (`make stress-sched`): runs the tests of the e2e stdlib fixtures
// with
// `MS_SCHED_STRESS=1`, where a promise never starts on its creator and the first idle thread
// takes it, so a timing bug that ordinarily shows once in N runs shows in every run. A
// file that fails under stress is run again without it: one that passes then is a
// stress-only failure (a real ordering bug) and fails this tool; one that also fails
// plain is reported and left to the ordinary suites. STRESS_JOBS sets the parallel runs
// (default: the CPU count); MS names the ms to run, which must embed a runtime built
// with the `sched-stress` feature (`make stress-sched` builds one at
// target/stress/release/ms). Arguments name the files to run (default:
// tests/conformance/fixtures/e2e/stdlib);
// `STRESS_CHANGED=<git ref>` runs only the test files changed since that ref.
// Usage: ms run tools/stress-sched.ms [-- files]
import (
	Promise, promise from "@std/concurrency/promise.ms",
	stdout from "@std/io/io.ms",
	arguments, working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	system_info from "@std/os/system.ms",
	seconds from "@std/time.ms",

	capture, env, tool_ms from "./lib.ms",
)

fixtures := "tests/conformance/fixtures/e2e/stdlib"

// Whether `ms test` is the fixture's own phase: a file declaring another phase (parse,
// check, run) is not meant to pass `ms test`.
fn has_tests(source String) Bool {
	if source.contains("// conform: phase=") {
		return source.contains("// conform: phase=test\n")
	}
	return source.starts_with("test \"") or source.contains("\ntest \"")
}

// One `ms test` run of `file`: its exit status and the last lines of its output.
fn test_run(ms, file String, stress Bool) Int {
	var settings = Map[String, String]()
	if stress { settings["MS_SCHED_STRESS"] = "1" }

	out := run(
		ms,
		["test", file.clone()],
		RunOptions(timeout: seconds(300), env: settings),
	).wait()
	if done := out { return done.exit_code }

	return 1
}

// Runs each file under stress; answers one report line per failure.
fn sweep(ms String, files List[String]) List[String] {
	var lines = List[String]()

	for f in files {
		lines.append("ran")
		if test_run(ms.clone(), f.clone(), true) == 0 { continue }

		if test_run(ms.clone(), f.clone(), false) == 0 {
			lines.append(
				f"stress: {f} fails under MS_SCHED_STRESS=1 and passes without it"
			)
		} else {
			lines.append(f"plain: {f} fails without stress too")
		}
	}

	return lines
}

// The e2e stdlib test files changed since `since`.
fn changed(since String) List[String] {
	var found = List[String]()
	text := capture(
		"git",
		[
			"diff",
			"--name-only",
			"--diff-filter=AM",
			since.clone(),
			"--",
			fixtures.clone(),
		],
	)

	for line in text.split("\n") {
		path := line.trim()
		if path.ends_with(".ms") { found.append(path.clone()) }
	}

	return found
}

fn main() Int {
	root := working_directory().get()
	var files = List[String]()
	for f in arguments() { files.append(f.clone()) }

	since := env("STRESS_CHANGED", "")

	if files.is_empty() and since != "" {
		files = changed(since)
	} else if files.is_empty() {
		for f in glob(fixtures, GlobOptions(patterns: ["*.ms"])).get_or([]) {
			files.append(f"{fixtures}/{f.path}")
		}
	}

	var tests = List[String]()

	for path in files {
		source := read_file(path.clone()).wait().get().decode_utf8() or ""
		if has_tests(source) { tests.append(path.clone()) }
	}

	ms := tool_ms(root)
	var jobs = system_info().cpu_count
	n := env("STRESS_JOBS", "").parse_int()
	if n != null { jobs = n }
	if jobs < 1 { jobs = 1 }

	var chunks = List[List[String]]()

	for worker in 0..jobs {
		var mine = List[String]()
		for i in 0..tests.length() {
			if i % jobs == worker {
				mine.append(tests[i].clone())
			}
		}
		chunks.append(mine)
	}

	var tasks = List[Promise[List[String]]]()

	for worker in 0..jobs {
		ms_copy := ms.clone()
		chunk := chunks[worker].clone()
		tasks.append(promise(() => ok(sweep(ms_copy, chunk))))
	}

	var ran = 0
	var broken = 0

	for task in tasks {
		for line in task.wait().get_or(List[String]()) {
			if line == "ran" {
				ran += 1
			} else {
				if line.starts_with("stress: ") { broken += 1 }
				print(f"{line}")
			}
		}
	}

	(
		stdout()
		.write(f"stress-sched: {ran} files, {broken} fail only under stress\n")
		.get()
	)
	if broken > 0 { return 1 }

	return 0
}
