// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

fn main() Unit!:
    return stdout().write(data: %q)
