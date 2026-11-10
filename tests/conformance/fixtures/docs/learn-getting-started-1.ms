// conform: tags=control-flow,diagnostics,interpolation,modules,stdlib-io,stdlib-process,tier-io
// conform: phase=check
// conform: origin=documentation/learn/getting-started.md:33
import arguments from "@std/os/env.ms"

export fn main() Int:
    print("Arguments: {arguments().length()}")
    return 0
