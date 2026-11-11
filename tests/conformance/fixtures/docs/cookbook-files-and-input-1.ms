// conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-process,tier-io,try-result
// conform: phase=check
// conform: origin=documentation/learn/common-tasks.md:94
import (
	arguments from "@std/os/env.ms",
	write_file from "@std/os/fs.ms",
)

fn run() Result[Unit, Error]:
	path := arguments().first().ok_or(
		Error("filesystem: invalid input", kind: "EINVAL")
	)?
	return write_file(path, "saved notes\n", replace: false).wait()

fn main() Unit!:
	run()?
