import redirect_to_null, StdStream, stderr, stdin, stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn shown(text: String) Int:
    if stdout().write(text).is_error():
        return 1

    return 0

export fn main() Int:
    if shown("before\n") != 0:
        return 1
    if redirect_to_null(StdStream.Output).is_error():
        return 2

    _ := stdout().write("hidden\n")
    if redirect_to_null(StdStream.Error).is_error():
        return 3

    _ := stderr().write("hidden\n")
    if redirect_to_null(StdStream.Input).is_error():
        return 4

    var input = lines(stdin())

    match input.next():
        ok(line):
            if line.is_some():
                return 5
        error(_):
            return 6

    return 0
