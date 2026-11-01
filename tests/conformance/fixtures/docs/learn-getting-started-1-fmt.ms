# conform: tags=control-flow,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
# conform: phase=parse
# conform: origin=documentation/learn/getting-started.md:33
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

export fn main() Int:
    let message = "Arguments: {arguments().length()}\n"
    if stdout().write(message).is_error():
        return 1

    return 0
