// conform: tags=diagnostics
// conform: phase=check
import (
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/process.ms",
)

export fn main() Int {
	args := arguments()
	_out := stdout().write(data: f"out={args[0]}\n")
	_err := stderr().write(data: "stderr\n")
	return 7
}
// expect-error: MS2002 5:5-5:14 module does not export arguments; another standard module exports it, so replace this import with: import arguments from "@std/os/env.ms"
// expect-error: MS2001 9:13 unknown binding arguments; add: import arguments from "@std/os/env.ms"
// expect-fix: 1:1-1:1 "import arguments from \"@std/os/env.ms\"\n"
// expect-error: MS3004 10:28 unknown argument data; parameters of write: value
// expect-error: MS3003 10:22 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS3004 11:28 unknown argument data; parameters of write: value
// expect-error: MS3003 11:22 missing argument value: String in call to write; add 'value: <String>'
