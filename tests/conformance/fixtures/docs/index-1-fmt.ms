# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
# conform: phase=parse
# conform: origin=documentation/_index.md:10
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let name = arguments().get(0, default: "world")
    let message = "Hello, {name}!\n"
    if stdout().write(message).is_error():
        return 1

    return 0
