// conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
// conform: phase=parse
// conform: origin=documentation/_index.md:10
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

fn main() Unit!:
    let name = arguments().get(0, default: "world")
    let message = "Hello, {name}!\n"
    try stdout().write(message)
