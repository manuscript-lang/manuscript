// conform: tags=control-flow,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
// conform: phase=parse
// conform: origin=documentation/learn/getting-started.md:33
import arguments from "@std/os/env.ms"

fn main() Unit:
    print("Arguments: {arguments().length()}")
