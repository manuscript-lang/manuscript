// conform: tags=testing,tier-stdlib
// conform: phase=run
import (
	StdStream, redirect_to_null, stderr, stdin, stdout from "@std/io/io.ms",
	lines from "@std/io/steps.ms",
)

fn shown(text String) Int {
	if stdout().write(text.clone()).is_error() { return 1 }
	return 0
}

export fn main() Int {
	if shown("before\n") != 0 { return 1 }
	if redirect_to_null(StdStream.Output).is_error() { return 2 }

	void stdout().write("hidden\n")
	if redirect_to_null(StdStream.Error).is_error() { return 3 }

	void stderr().write("hidden\n")
	if redirect_to_null(StdStream.Input).is_error() { return 4 }

	var input = lines(stdin())

	match input.next() {
		ok(line) => {
			if line != null { return 5 }
		}
		error(_) => {
			return 6
		}
	}

	return 0
}
// expect-exit: 0
// expect-stdout: before
