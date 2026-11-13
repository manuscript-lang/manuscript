// Ownership count gate (`make count-check`): runs the programs of
// tests/ownership-counts in Debug and Release against a runtime built with counters
// (`ms-rt` feature `stats`) and compares what they report with the `// expect-debug:`
// and
// `// expect-release:` headers (`key=value` pairs from the runtime's "ms-rt counts:" line; absent keys are not checked)
// and `// expect-stdout:` lines (the program's stdout, in order, on both). Cleanup
// order is the stdout lines. A fixture must exit successfully before its counts or
// output can satisfy the gate. The counts start when the program's `main` begins, so
// the runtime's own start-up records are not in them. A change may not raise a count
// without a stated reason; update the header in the same change. MS names the ms that
// runs the programs (default target/release/ms). Usage: ms run tools/count-check.ms [--
// files]
import (
	stdout from "@std/io/io.ms",
	arguments,
	change_directory,
	set_environment,
	working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file, temporary from "@std/os/fs.ms",
	run from "@std/os/process.ms",

	tool_ms, use_stats_runtime from "./lib.ms",
)

// The text after `prefix` on every line that starts with it.
fn after(text: String, prefix: String) List[String]:
	var found = List[String]()
	for line in text.split("\n"):
		if line.starts_with(prefix): found.append(
			line.slice(prefix.length(), line.length()).get("")
		)
	return found

fn main() Int:
	code := use_stats_runtime()
	if code != 0: return code

	// LLVM would delete blocks nothing reads; the gate counts every block the compiler
	// asks for.
	set_environment("MS_HEAP_FACTS", "off").get()

	root := working_directory().get()
	var files = List[String]()
	for f in arguments(): files.append(f.clone())
	if files.is_empty():
		for f in glob("tests/ownership-counts", GlobOptions(patterns: ["*.ms"])).get([]):
			files.append("tests/ownership-counts/{f.path}")

	ms := tool_ms(root.clone())
	scratch := temporary("ms-counts-").get()
	change_directory(scratch.path()).get()

	var failures = 0
	var checked = 0

	for f in files:
		source := read_file("{root}/{f}").wait().get().decode_utf8().get("")
		expected_out := after(source, "// expect-stdout: ")

		for build in ["debug", "release"]:
			ran := run(ms.clone(), ["run", "{root}/{f}", "--build-type", build.clone()]).wait()
			checked += 1

			if ran.is_error():
				failures += 1

				cause := ran.err().message.clone()
				(
					stdout()
					.write(
						"run: {f} ({build}) could not run {ms}: {cause}; check MS and the fixture's process/output limits\n"
					)
					.get()
				)
				continue

			child := ran.get()
			out := child.stdout.decode_utf8().get("")
			err := child.stderr.decode_utf8().get("")

			if child.exit_code != 0:
				failures += 1
				(
					stdout()
					.write(
						"exit: {f} ({build}) exited {child.exit_code}; fix the fixture failure\n{err}"
					)
					.get()
				)
				continue

			counts := after(err, "ms-rt counts: ")
			live := after(err, "ms-rt live blocks at exit: ")

			if live.is_empty() or live[0] != "0":
				failures += 1

				shown := if not live.is_empty(): live[0].clone() else: "an unreported number of"
				print("leak: {f} ({build}) left {shown} live blocks")

			var have = List[String]()
			if not counts.is_empty(): have = counts[0].split(" ").clone()

			for header in after(source, "// expect-{build}: "):
				for pair in header.split(" "):
					if pair == "": continue

					checked += 1

					want := pair.clone()

					if not have.contains(want):
						failures += 1
						(
							stdout()
							.write(
								"count: {f} ({build}) wants {want}; runtime reported: {counts.join(" ")}\n"
							)
							.get()
						)

			if not expected_out.is_empty():
				checked += 1

				if out.trim_end() != expected_out.join("\n"):
					failures += 1
					print("stdout: {f} ({build}) differs:\n{out}")

	change_directory(root).get()
	print("checked {checked} expectations, {failures} failing")

	if checked == 0:
		print("no expectations ran")
		return 1

	if failures > 0: return 1

	return 0
