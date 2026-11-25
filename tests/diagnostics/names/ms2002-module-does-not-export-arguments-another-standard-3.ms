// conform: tags=diagnostics
// conform: phase=check
import (
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/process.ms",
)

export fn main() Int {
	args := arguments()

	if args.length() > 0 and args[0] == "binary" {
		_raw := stdout().write_bytes(
			data: "x".to_bytes().with_value(index: 0, value: 255)
		)
		return 0
	}

	_out := stdout().write(data: "stdout\n")
	_err := stderr().write(data: "stderr\n")
	var index = 0

	while index < args.length() {
		_arg := stdout().write(data: f"arg={args[index]}\n")
		index += 1
	}

	if args.length() > 0 and args[0] == "fail" {
		return 23
	}

	return 0
}
// expect-error: MS2002 5:5-5:14 module does not export arguments; another standard module exports it, so replace this import with: import arguments from "@std/os/env.ms"
// expect-error: MS2001 9:13 unknown binding arguments; add: import arguments from "@std/os/env.ms"
// expect-fix: 1:1-1:1 "import arguments from \"@std/os/env.ms\"\n"
// expect-error: MS2001 12:26 unknown or ambiguous member write_bytes on WriteStream[String]; available: close, end, flush, sink, write
// expect-error: MS3004 18:28 unknown argument data; parameters of write: value
// expect-error: MS3003 18:22 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS3004 19:28 unknown argument data; parameters of write: value
// expect-error: MS3003 19:22 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS3004 23:32 unknown argument data; parameters of write: value
// expect-error: MS3003 23:26 missing argument value: String in call to write; add 'value: <String>'
