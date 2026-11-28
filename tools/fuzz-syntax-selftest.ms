// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// The differential generator must emit programs in the current syntax. `program` has to
// type-check, and `type_error` has to fail in checking rather than in parsing.
import (
	Bytes from "@std/bytes.ms",
	working_directory from "@std/os/env.ms",
	temporary, write_file from "@std/os/fs.ms",
	run from "@std/os/process.ms",

	program, type_error from "./conform/fuzz.ms",
	tool_ms from "./lib.ms",
)

fn output_text(stdout, stderr Bytes) String {
	return (stderr.decode_utf8() or "") + (stdout.decode_utf8() or "")
}

fn check_file(ms, dir, name, source String) String! {
	path := f"{dir}/{name}"
	void write_file(path.clone(), source).wait()?

	out := run(ms, ["check", "--only", "types", path]).wait()?
	text := output_text(out.stdout, out.stderr)
	if out.exit_code == 0 { return ok("") }

	return ok(text)
}

fn main() Int {
	root := working_directory().get()
	ms := tool_ms(root.clone())
	scratch := temporary("fuzz-syntax-").get()
	dir := scratch.path()
	var failed = 0

	for seed in 0..12 {
		checked := check_file(
			ms,
			dir.clone(),
			f"program-{seed}.ms",
			program(seed).source,
		)

		if checked.is_error() {
			print(checked.err().message)
			return 1
		}

		problem := checked.get()

		if problem != "" {
			print(f"program({seed}) did not type-check:\n{problem}")
			failed += 1
		}

		typed := check_file(ms, dir.clone(), f"type-{seed}.ms", type_error(seed).source)

		if typed.is_error() {
			print(typed.err().message)
			return 1
		}

		bad := typed.get()

		if bad == "" or bad.contains("parse:") {
			print(f"type_error({seed}) was not a check failure:\n{bad}")
			failed += 1
		}
	}

	if failed != 0 { return 1 }

	return 0
}
