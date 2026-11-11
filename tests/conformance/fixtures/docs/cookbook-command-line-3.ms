// conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=check
// conform: origin=documentation/learn/common-tasks.md:63
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
)

fn run() Result[Unit, Error]:
	path := arguments().first().ok_or(
		Error("filesystem: invalid input", kind: "EINVAL")
	)?
	text := read_file(path, max_bytes: 1048576).wait()? | .decode_utf8().ok_or(
		Error("filesystem: invalid data", kind: "EBADMSG")
	)?
	stdout().write(text)?
	return stdout().flush()

fn main() Unit!:
	run()?
