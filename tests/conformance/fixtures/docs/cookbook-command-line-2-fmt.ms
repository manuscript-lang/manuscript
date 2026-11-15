// conform: tags=control-flow,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:39
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Void, Error]:
    for name in arguments():
        stdout().write(f"Hello, {name}!\n")?
    return stdout().flush()

fn main() Void!:
    run()?
