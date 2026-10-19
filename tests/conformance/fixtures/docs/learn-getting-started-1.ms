# conform: tags=control-flow,diagnostics,interpolation,modules,stdlib-io,stdlib-process,tier-io
# conform: phase=check
# conform: origin=documentation/learn/getting-started.md:33
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let message = "Arguments: {arguments().length()}\n"
    if stdout().write(message).is_error():
        return 1
    return 0
