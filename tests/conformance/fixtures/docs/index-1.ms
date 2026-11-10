// conform: tags=control-flow,diagnostics,faults,interpolation,modules,stdlib-io,stdlib-process,tier-io
// conform: phase=check
// conform: origin=documentation/_index.md:10
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

fn main() Unit!:
    let name = arguments().get(0, default: "world")
    let message = "Hello, {name}!\n"
    try stdout().write(message)
    return ok(unit)
