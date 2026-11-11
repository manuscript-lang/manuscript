// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

fn never() Int:
    return 1

fn main() Unit:
    _written := stdout().write(data: "TARGET_RAN\n")
