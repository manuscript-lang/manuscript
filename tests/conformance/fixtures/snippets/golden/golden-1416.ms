// conform: tags=diagnostics
// conform: phase=check
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"
import stderr from "@std/io/io.ms"

fn write_line(text: String) Result[Unit, Error]:
    stdout().write(data: "{text}\n")?

fn exercise() Result[Int, Error]:
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
            written := stderr().write("{cause.message()}\n")
            return 1

test "selected=a=b":
    write_line("selected")?

test "unselected":
    write_line("unselected")
