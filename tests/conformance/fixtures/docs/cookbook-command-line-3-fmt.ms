// conform: tags=control-flow,formatter,modules,parser,stdlib-fs,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:63
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
)

fn run() Result[Void, Error] {
	path := ok_or(
		arguments().first(),
		Error("filesystem: invalid input", kind: "EINVAL"),
	)?
	text := ok_or(
		read_file(path, max_bytes: 1048576).wait()? | .decode_utf8(),
		Error("filesystem: invalid data", kind: "EBADMSG"),
	)?
	stdout().write(text)?
	return stdout().flush()
}

fn main() Void! {
	run()?
}
