// Checks the Manuscript command-line front against the Rust `ms` on the argument lines
// in tools/ms/cases.txt. For each line: when the Rust `ms` rejects it with status 2, or
// the front answers by itself, output and status must be identical; otherwise the front
// must hand the command to the Rust `ms`. Usage: ms run tools/ms-cli-check.ms [--
// path/to/ms [path/to/libmstool.a]]
import (
	Bytes from "@std/bytes.ms",
	arguments from "@std/os/env.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",

	note from "./lib.ms",
)

fn text(bytes: Bytes) String:
	return bytes.decode_utf8().get_or("")

fn main() Int:
	args := arguments()
	rust := args.get_or(0, "target/release/ms")
	link := args.get_or(1, "target/c-tool/libmstool.a")
	cases := text(read_file("tools/ms/cases.txt").wait().get())
	var failures = 0

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

		if expected.exit_code == 2 or not delegated:
			same := (
				expected.exit_code == front.exit_code
				and expected.stdout == front.stdout
				and expected.stderr == front.stderr
			)

			if not same:
				note(f"DIFF [{line}] rust={expected.exit_code} front={front.exit_code}")
				failures += 1

	if failures > 0: return 1

	note("front matches the Rust ms")
	return 0
