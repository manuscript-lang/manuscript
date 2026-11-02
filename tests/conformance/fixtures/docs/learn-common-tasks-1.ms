# conform: tags=control-flow,modules,stdlib-io,tier-core,try-result
# conform: phase=run
# conform: origin=documentation/learn/common-tasks.md:15
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    try stdout().write("Hello, Manuscript!\n")
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1

    return 0
