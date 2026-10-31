import redirect_to_null, StdStream, stderr from "@std/io.ms"

export fn main() Int:
    if redirect_to_null(StdStream.Error).is_error():
        return 3
    let _ = stderr().write("hidden\n")
    return 0
