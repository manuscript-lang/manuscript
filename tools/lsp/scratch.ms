// Scratch copies of open buffers. The checker and the formatter read files, so an
// unsaved buffer is written beside its file under a hidden name (relative imports still
// resolve), handed to `$MS_RUST_CLI` (as in tools/ms/main.ms, else `ms-rust`), and
// removed again. This goes away when the C checker takes text directly.
import (
	environment from "@std/os/env.ms",
	read_file, remove, write_file from "@std/os/fs.ms",
	basename, dirname, join from "@std/os/path.ms",
	CommandOutput, run from "@std/os/process.ms",
)

// The hidden file name for a buffer of `path`.
export fn scratch_name(path: String) String: f".ms-lsp-{basename(path)}"

fn program() String:
	env := environment().get_or(Map[String, String]())
	return env.get("MS_RUST_CLI").get_or("ms-rust")

// What a command left behind: its output and the scratch file's text afterwards (the
// formatter rewrites the file in place).
export type Scratched:
	output: CommandOutput
	text: String

// Writes `source` as the scratch copy of `path`, runs `command` on it (the scratch path
// is its last argument), reads the copy back, removes it, and returns both.
export fn run_on_scratch(
	path: String,
	source: String,
	command: List[String],
) Result[Scratched, Error]:
	scratch := join([dirname(path), scratch_name(path)])
	written := write_file(scratch.clone(), source, replace: true).wait()
	if written.is_error(): return error(written.err())

	var arguments = command.clone()
	arguments.append(scratch.clone())

	ran := run(program(), arguments).wait()

	if ran.is_error():
		remove(scratch).get_or(void)
		return error(ran.err())

	after := read_file(scratch.clone()).wait()
	remove(scratch).get_or(void)
	if after.is_error(): return error(after.err())

	return ok(Scratched(output: ran.get(), text: after.get().decode_utf8().get_or("")))
