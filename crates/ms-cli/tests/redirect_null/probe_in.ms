import redirect_to_null, read_line, StdStream, stdin from "@std/io.ms"

export fn main() Int:
    if redirect_to_null(StdStream.Input).is_error():
        return 4
    match read_line(stdin()):
        ok(line):
            if line.is_some():
                return 5
        error(_):
            return 6
    return 0
