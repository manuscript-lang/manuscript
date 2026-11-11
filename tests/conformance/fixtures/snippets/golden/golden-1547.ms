// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

export fn main() Int:
    match stdout().write(data: %q):
        ok(_):
            return 0
        error(_):
            return 1
