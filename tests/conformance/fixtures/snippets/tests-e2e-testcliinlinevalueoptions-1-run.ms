# conform: tags=control-flow,interpolation,match,modules,mutation,stdlib-io,stdlib-process,strings,testing,tier-io,try-result
# conform: phase=run
# conform: origin=tests/e2e/cli_options_test.go:14 TestCLIInlineValueOptions
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout
from "@std/io.ms" import stderr

def write_line(text: String) -> Result[Unit, Error]:
    try stdout().write(data: f"{text}\n")
    return ok(())

def exercise() -> Result[Int, Error]:
    let args = arguments()
    var index = 0

    while index < args.length():
        try write_line(args[index])
        index = index + 1

    return ok(0)

export def main() -> Int:
    match exercise():
        case ok(status): return status
        case error(cause):
            let _written = stderr().write(f"{cause.message()}\n")
            return 1

test "selected=a=b":
    try write_line("selected")

test "unselected":
    try write_line("unselected")
