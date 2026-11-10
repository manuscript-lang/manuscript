// conform: tags=control-flow,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:39
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    for name in arguments():
        try stdout().write("Hello, {name}!\n")
    return stdout().flush()

fn main() Unit!:
    try run()
    return ok(unit)
