# conform: tags=control-flow,interpolation,match,modules,mutation,stdlib-io,stdlib-process,strings,testing,tier-io,try-result
# conform: phase=run
# conform: origin=tests/e2e/cli_options_test.go:14 TestCLIInlineValueOptions
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"
import stderr from "@std/io.ms"

fn write_line(text: String) Result[Unit, Error]:
    try stdout().write(data: "{text}\n")
    return ok(unit)

fn exercise() Result[Int, Error]:
    let args = arguments()
    var index = 0

    while index < args.length():
        try write_line(args[index])
        index = index + 1

    return ok(0)

export fn main() Int:
    match exercise():
        ok(status): return status
        error(cause):
            let written = stderr().write("{cause.message()}\n")
            return 1

test "selected=a=b":
    try write_line("selected")

test "unselected":
    write_line("unselected")
