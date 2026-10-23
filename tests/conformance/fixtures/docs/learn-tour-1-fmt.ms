# conform: tags=control-flow,formatter,modules,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:15
import stdout from "@std/io.ms"

export fn main() Int:
    if stdout().write("Hello, Manuscript!\n").is_error():
        return 1

    return 0
