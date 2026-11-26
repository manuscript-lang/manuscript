// conform: tags=control-flow,diagnostics,formatter,modules,stdlib-fs,stdlib-process,tier-io,try-result
// conform: phase=check,parse
// conform: origin=documentation/learn/common-tasks.md:94
import (
	arguments from "@std/os/env.ms",
	write_file from "@std/os/fs.ms",
)

fn run() Result[Void, Error] {
	path := ok_or(
		arguments().first(),
		Error("filesystem: invalid input", kind: "EINVAL"),
	)?
	return write_file(path, "saved notes\n", replace: false).wait()
}

fn main() Void! {
	run()?
}
// expect-exit: 0
