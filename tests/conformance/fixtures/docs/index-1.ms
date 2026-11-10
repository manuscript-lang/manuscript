// conform: tags=control-flow,diagnostics,faults,interpolation,modules,stdlib-io,stdlib-process,tier-io
// conform: phase=check
// conform: origin=documentation/_index.md:10
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

export fn main() Int:
    name := arguments().get(0, default: "world")
    message := "Hello, {name}!\n"
    if stdout().write(message).is_error():
        return 1

    return 0
