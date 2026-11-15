// conform: tags=control-flow,diagnostics,interpolation,modules,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=check
// conform: origin=documentation/learn/common-tasks.md:39
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Void, Error]:
    for name in arguments():
        stdout().write(f"Hello, {name}!\n")?
    return stdout().flush()

fn main() Void!:
    run()?
