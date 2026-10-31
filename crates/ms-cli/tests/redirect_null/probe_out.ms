import redirect_to_null, StdStream, stdout from "@std/io.ms"

export fn main() Int:
    if redirect_to_null(StdStream.Output).is_error():
        return 2
    let _ = stdout().write("hidden\n")
    return 0
