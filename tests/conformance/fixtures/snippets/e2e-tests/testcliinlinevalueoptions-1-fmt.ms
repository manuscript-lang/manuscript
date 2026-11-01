# conform: tags=control-flow,formatter,interpolation,match,modules,mutation,parser,stdlib-io,stdlib-process,strings,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/cli_options_test.go:14 TestCLIInlineValueOptions
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"
import stderr from "@std/io/io.ms"

fn write_line(text: String) Unit!:
    try stdout().write(data: "{text}\n")
    return ok(unit)

fn exercise() Int!:
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
            let _written = stderr().write("{cause.message()}\n")
            return 1

test "selected=a=b":
    try write_line("selected")

test "unselected":
    try write_line("unselected")
