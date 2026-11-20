// Checks the Manuscript command-line front on the argument lines in tools/ms/cases.txt.
// Against the Rust `ms`: a line the Rust `ms` rejects with status 2 must exit 2 in the
// front, and a line the front hands over (`delegate ...`) must not be one Rust rejects.
// Against tools/ms/cases.golden: the exact output of every usage error and help
// request. Usage: ms run tools/ms-cli-check.ms [-- path/to/ms [path/to/libmstool.a
// [--update]]];
// --update rewrites the golden file from the front's current output.
import (
	Bytes from "@std/bytes.ms",
	arguments from "@std/os/env.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",

	note from "./lib.ms",
)

fn text(bytes: Bytes) String:
	return bytes.decode_utf8().get_or("")

// Whether the golden file records the output of this line: usage errors and help.
fn recorded(line: String, status: Int, delegated: Bool) Bool:
	if delegated: return false
	if status == 2: return true

	return (
		line.starts_with("help")
		or line.ends_with("--help")
		or line.ends_with(" -h")
		or line == "-h"
	)

fn main() Int:
	args := arguments()
	rust := args.get_or(0, "target/release/ms")
	link := args.get_or(1, "target/c-tool/libmstool.a")
	update := args.get_or(2, "") == "--update"
	cases := text(read_file("tools/ms/cases.txt").wait().get())
	var failures = 0
	var golden = ""

	for line in cases.lines():
		if line.is_empty(): continue

		words := line.split(" ")
		expected := run(rust, words).wait().get()
		var plan = Map[String, String]()
		plan.add("MS_CLI_PLAN", "1")

		front := run(
			rust,
			[
				"run",
				"tools/ms/main.ms",
				"--link",
				link.clone(),
				"--",
			].concat(words),
			RunOptions(env: plan),
		).wait().get()
		delegated := text(front.stdout).starts_with("delegate ")

		if expected.exit_code == 2 and front.exit_code != 2:
			note(f"DIFF [{line}] rust=2 front={front.exit_code}")
			failures += 1
		else if delegated and expected.exit_code == 2:
			note(f"DIFF [{line}] rust=2 but the front delegates it")
			failures += 1

		if recorded(line, front.exit_code, delegated):
			golden += f"== {line}\nstatus {front.exit_code}\n{text(front.stdout)}--- stderr\n{text(front.stderr)}\n"

	if update:
		write_file("tools/ms/cases.golden", golden.to_bytes(), replace: true).wait().get()
		note("rewrote tools/ms/cases.golden")
	else if golden != text(read_file("tools/ms/cases.golden").wait().get()):
		note("DIFF tools/ms/cases.golden; run with --update to review the change")
		failures += 1

	if failures > 0: return 1

	note("front matches the Rust ms exit statuses and the golden output")
	return 0
