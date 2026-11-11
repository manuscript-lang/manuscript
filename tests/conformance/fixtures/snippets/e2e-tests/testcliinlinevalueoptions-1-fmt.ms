// conform: tags=control-flow,formatter,interpolation,match,modules,mutation,parser,stdlib-io,stdlib-process,strings,testing,tier-io,try-result
// conform: phase=parse
// conform: origin=tests/e2e/cli_options_test.go:14 TestCLIInlineValueOptions
import (
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

fn write_line(text: String) Unit!:
	stdout().write("{text}\n")?

fn exercise() Int!:
	args := arguments()
	var index = 0

	while index < args.length():
		write_line(args[index])?
		index += 1

	return ok(0)

export fn main() Int:
	match exercise():
		ok(status): return status
		error(cause):
			_written := stderr().write("{cause.message}\n")
			return 1

test "selected=a=b":
	write_line("selected")?

test "unselected":
	write_line("unselected")?
