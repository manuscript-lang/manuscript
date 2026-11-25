// conform: tags=diagnostics
// conform: phase=check
import (
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/process.ms",
)

fn write_line(text String) Result[Void, Error] {
	stdout().write(data: f"{text}\n")?
}

fn exercise() Result[Int, Error] {
	args := arguments()
	var index = 0

	while index < args.length() {
		write_line(args[index])?
		index += 1
	}

	return ok(0)
}

export fn main() Int {
	match exercise() {
		ok(status) => return status
		error(cause) => {
			written := stderr().write(f"{cause.message()}\n")
			return 1
		}
	}
}

test "selected=a=b" {
	write_line("selected")?
}

test "unselected" {
	write_line("unselected")
}
// expect-error: MS2002 5:5-5:14 module does not export arguments; another standard module exports it, so replace this import with: import arguments from "@std/os/env.ms"
// expect-error: MS3004 9:20 unknown argument data; parameters of write: value
// expect-error: MS3003 9:14 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS2001 13:13 unknown binding arguments; add: import arguments from "@std/os/env.ms"
// expect-fix: 1:1-1:1 "import arguments from \"@std/os/env.ms\"\n"
// expect-error: MS3000 28:48 cause.message is not a function (it has type String); only functions and methods can be called, so remove the (...) or call a function instead
// expect-error: MS3000 39:5 this statement discards Result[Void, Error], so a failure would be lost; write a trailing '?' to propagate it, 'if value := x' or 'match' to handle it, or 'void ...' to drop it on purpose
