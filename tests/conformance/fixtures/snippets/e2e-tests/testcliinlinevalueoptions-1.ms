// conform: tags=control-flow,interpolation,match,modules,mutation,stdlib-io,stdlib-process,strings,testing,tier-io,try-result
// conform: phase=test
// conform: origin=tests/e2e/cli_options_test.go:14 TestCLIInlineValueOptions
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"
import stderr from "@std/io/io.ms"

fn write_line(text: String) Unit!:
    stdout().write("{text}\n")?

fn exercise() Int!:
    args := arguments()
    var index = 0

    while index < args.length():
        write_line(args[index])?
        index = index + 1

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
