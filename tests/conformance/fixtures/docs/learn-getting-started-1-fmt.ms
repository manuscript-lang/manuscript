// conform: tags=control-flow,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
// conform: phase=parse
// conform: origin=documentation/learn/getting-started.md:33
import arguments from "@std/os/env.ms"

export fn main() Int:
    print("Arguments: {arguments().length()}")
    return 0
